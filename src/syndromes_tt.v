/* verilator lint_off TIMESCALEMOD */

`timescale 1ns / 1ps

//****************
// Module: bch_syndrome_tt
// File:   bch_syndrome_tt.v
// Description: Bit-serial syndrome calculation for BCH(59,35) over GF(2^6).
// Target board: GF180 ASIC TT run
// Author: Fco. Javier Rubio (Cleaned and Validated for ASIC Synthesis)
// Last update: 2026-06-16
//****************

module bch_syndrome_tt #(parameter M=6, T=4, P=1, N_PAD=64)(
    input  wire clk,
    input  wire rst_n,
    input  wire valid_in,
    input  wire sop_in,
    input  wire [P-1:0] data_in,
    output wire [(2*T*M)-1:0] syndromes,
    output reg  done
);

    // -------------------------------------------------------------------------
    // 1. Internal Registers & Output Unpacking
    // -------------------------------------------------------------------------
    localparam MAX_CYCLES = (N_PAD / P) - 1;

    reg [M-1:0] syn_reg [1:2*T];
    reg [5:0]   cycle_cnt;

    // Pack the 2D array into the flat 1D output vector
    genvar i;
    generate
        for (i = 1; i <= 2*T; i = i + 1) begin : pack_syn
            assign syndromes[(i*M)-1 : (i-1)*M] = syn_reg[i];
        end
    endgenerate

    // -------------------------------------------------------------------------
    // 2. ASIC Optimized Combinational Multiplier Network
    // -------------------------------------------------------------------------
    // We compute the Horner's rule multiplication combinational paths onto wires.
    // This allows ABC to perfectly map the XOR matrix without timing check glitches.
    wire [M-1:0] next_syn_1 = mult_alpha_1(syn_reg[1]) ^ {{M-1{1'b0}}, data_in};
    wire [M-1:0] next_syn_2 = mult_alpha_2(syn_reg[2]) ^ {{M-1{1'b0}}, data_in};
    wire [M-1:0] next_syn_3 = mult_alpha_3(syn_reg[3]) ^ {{M-1{1'b0}}, data_in};
    wire [M-1:0] next_syn_4 = mult_alpha_4(syn_reg[4]) ^ {{M-1{1'b0}}, data_in};
    wire [M-1:0] next_syn_5 = mult_alpha_5(syn_reg[5]) ^ {{M-1{1'b0}}, data_in};
    wire [M-1:0] next_syn_6 = mult_alpha_6(syn_reg[6]) ^ {{M-1{1'b0}}, data_in};
    wire [M-1:0] next_syn_7 = mult_alpha_7(syn_reg[7]) ^ {{M-1{1'b0}}, data_in};
    wire [M-1:0] next_syn_8 = mult_alpha_8(syn_reg[8]) ^ {{M-1{1'b0}}, data_in};

    // -------------------------------------------------------------------------
    // 3. Serial Accumulation State Machine (Clean Sequential Block)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done       <= 1'b0;
            cycle_cnt  <= 6'd0;
            syn_reg[1] <= {M{1'b0}};
            syn_reg[2] <= {M{1'b0}};
            syn_reg[3] <= {M{1'b0}};
            syn_reg[4] <= {M{1'b0}};
            syn_reg[5] <= {M{1'b0}};
            syn_reg[6] <= {M{1'b0}};
            syn_reg[7] <= {M{1'b0}};
            syn_reg[8] <= {M{1'b0}};
        end else begin
            done <= 1'b0; // Default to low

            if (valid_in) begin
                if (sop_in) begin
                    // On Start of Packet, initialize registers with the first data bit
                    cycle_cnt  <= 6'd0;
                    syn_reg[1] <= {{M-1{1'b0}}, data_in};
                    syn_reg[2] <= {{M-1{1'b0}}, data_in};
                    syn_reg[3] <= {{M-1{1'b0}}, data_in};
                    syn_reg[4] <= {{M-1{1'b0}}, data_in};
                    syn_reg[5] <= {{M-1{1'b0}}, data_in};
                    syn_reg[6] <= {{M-1{1'b0}}, data_in};
                    syn_reg[7] <= {{M-1{1'b0}}, data_in};
                    syn_reg[8] <= {{M-1{1'b0}}, data_in};
                end else begin
                    cycle_cnt  <= cycle_cnt + 1'b1;
                    
                    // Safely sample pre-calculated combinational wires into the registers
                    syn_reg[1] <= next_syn_1;
                    syn_reg[2] <= next_syn_2;
                    syn_reg[3] <= next_syn_3;
                    syn_reg[4] <= next_syn_4;
                    syn_reg[5] <= next_syn_5;
                    syn_reg[6] <= next_syn_6;
                    syn_reg[7] <= next_syn_7;
                    syn_reg[8] <= next_syn_8;
                end
                
                // Assert done precisely when the 64th bit is accumulated
                if ((cycle_cnt == MAX_CYCLES - 1) && !sop_in) begin
                    done <= 1'b1;
                    // Telemetry $displays removed to avoid unmapped instance issues on GitHub Actions.
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // 4. Generated GF(2^6) Pure Logic Combinational Functions
    // -------------------------------------------------------------------------
    function [5:0] mult_alpha_1;
        input [5:0] d;
        begin
            mult_alpha_1[0] = d[5];
            mult_alpha_1[1] = d[0] ^ d[5];
            mult_alpha_1[2] = d[1];
            mult_alpha_1[3] = d[2];
            mult_alpha_1[4] = d[3];
            mult_alpha_1[5] = d[4];
        end
    endfunction

    // Multiplication functions remain exactly as you defined them, 
    // but now they operate in pure logic mode outside the synchronous assignment.
    function [5:0] mult_alpha_2;
        input [5:0] d;
        begin
            mult_alpha_2[0] = d[4];
            mult_alpha_2[1] = d[4] ^ d[5];
            mult_alpha_2[2] = d[0] ^ d[5];
            mult_alpha_2[3] = d[1];
            mult_alpha_2[4] = d[2];
            mult_alpha_2[5] = d[3];
        end
    endfunction

    function [5:0] mult_alpha_3;
        input [5:0] d;
        begin
            mult_alpha_3[0] = d[3];
            mult_alpha_3[1] = d[3] ^ d[4];
            mult_alpha_3[2] = d[4] ^ d[5];
            mult_alpha_3[3] = d[0] ^ d[5];
            mult_alpha_3[4] = d[1];
            mult_alpha_3[5] = d[2];
        end
    endfunction

    function [5:0] mult_alpha_4;
        input [5:0] d;
        begin
            mult_alpha_4[0] = d[2];
            mult_alpha_4[1] = d[2] ^ d[3];
            mult_alpha_4[2] = d[3] ^ d[4];
            mult_alpha_4[3] = d[4] ^ d[5];
            mult_alpha_4[4] = d[0] ^ d[5];
            mult_alpha_4[5] = d[1];
        end
    endfunction

    function [5:0] mult_alpha_5;
        input [5:0] d;
        begin
            mult_alpha_5[0] = d[1];
            mult_alpha_5[1] = d[1] ^ d[2];
            mult_alpha_5[2] = d[2] ^ d[3];
            mult_alpha_5[3] = d[3] ^ d[4];
            mult_alpha_5[4] = d[4] ^ d[5];
            mult_alpha_5[5] = d[0] ^ d[5];
        end
    endfunction

    function [5:0] mult_alpha_6;
        input [5:0] d;
        begin
            mult_alpha_6[0] = d[0] ^ d[5];
            mult_alpha_6[1] = d[0] ^ d[1] ^ d[5];
            mult_alpha_6[2] = d[1] ^ d[2];
            mult_alpha_6[3] = d[2] ^ d[3];
            mult_alpha_6[4] = d[3] ^ d[4];
            mult_alpha_6[5] = d[4] ^ d[5];
        end
    endfunction

    function [5:0] mult_alpha_7;
        input [5:0] d;
        begin
            mult_alpha_7[0] = d[4] ^ d[5];
            mult_alpha_7[1] = d[0] ^ d[4];
            mult_alpha_7[2] = d[0] ^ d[1] ^ d[5];
            mult_alpha_7[3] = d[1] ^ d[2];
            mult_alpha_7[4] = d[2] ^ d[3];
            mult_alpha_7[5] = d[3] ^ d[4];
        end
    endfunction

    function [5:0] mult_alpha_8;
        input [5:0] d;
        begin
            mult_alpha_8[0] = d[3] ^ d[4];
            mult_alpha_8[1] = d[3] ^ d[5];
            mult_alpha_8[2] = d[0] ^ d[4];
            mult_alpha_8[3] = d[0] ^ d[1] ^ d[5];
            mult_alpha_8[4] = d[1] ^ d[2];
            mult_alpha_8[5] = d[2] ^ d[3];
        end
    endfunction

endmodule
