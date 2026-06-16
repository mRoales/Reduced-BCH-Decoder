/* verilator lint_off TIMESCALEMOD */

`timescale 1ns / 1ps

//****************
// Module: bch_kes_ibma_tt - Reformulated iBMA (RiBM)
// File:   bch_kes_ibma_tt.v
// Description: Zero-MUX, parallel-update serial iBMA for BCH(59,35).
// Target board: GF180 ASIC TT run
// Author: Fco. Javier Rubio (Fixed and Closed for ASIC Synthesis)
// Last update: 2026-06-16
//****************

module bch_kes_ibma_tt #(parameter M=6, T=4)(
    input  wire clk, rst_n, start,
    input  wire [(2*T*M)-1:0]   syndromes,
    output wire [((T+1)*M)-1:0] locator_poly, 
    output reg  done, uncorrectable, 
    output wire [4:0] L_out
);

    // -------------------------------------------------------------------------
    // 1. Combinational GF(2^6) Multiplier Function
    // -------------------------------------------------------------------------
    function [M-1:0] gf_mult;
        input [M-1:0] a;
        input [M-1:0] b;
        reg   [M-1:0] p;
        integer idx;
        begin
            p = {M{1'b0}};
            for (idx = 0; idx < M; idx = idx + 1) begin
                if (b[idx]) p = p ^ a;
                a = (a[M-1]) ? ({a[M-2:0], 1'b0} ^ 6'h03) : {a[M-2:0], 1'b0};
            end
            gf_mult = p;
        end
    endfunction

    // -------------------------------------------------------------------------
    // 2. Data Path & Control Registers
    // -------------------------------------------------------------------------
    reg [((T+1)*M)-1:0] Lambda_flat;
    reg [((T+1)*M)-1:0] B_flat;
    reg [M-1:0] gamma;
    reg [M-1:0] delta_comb;
    reg [4:0]   L;
    reg         update_B_flag;

    reg [1:0] state;
    reg [2:0] k;
    reg [4:0] r;

    localparam IDLE       = 2'b00;
    localparam CALC_DELTA = 2'b01;
    localparam UPDATE     = 2'b10;

    assign locator_poly = Lambda_flat;
    assign L_out        = L;

    // -------------------------------------------------------------------------
    // 3. Static Multiplexers with Default Cases (Prevents Latches)
    // -------------------------------------------------------------------------
    reg [M-1:0] current_Lambda;
    always @(*) begin
        case(k)
            3'd0: current_Lambda = Lambda_flat[0*M +: M];
            3'd1: current_Lambda = Lambda_flat[1*M +: M];
            3'd2: current_Lambda = Lambda_flat[2*M +: M];
            3'd3: current_Lambda = Lambda_flat[3*M +: M];
            3'd4: current_Lambda = Lambda_flat[4*M +: M];
            default: current_Lambda = {M{1'b0}};
        endcase
    end

    reg [M-1:0] prev_B;
    always @(*) begin
        case(k)
            3'd0: prev_B = B_flat[0*M +: M]; // Organically handle k=0
            3'd1: prev_B = B_flat[0*M +: M];
            3'd2: prev_B = B_flat[1*M +: M];
            3'd3: prev_B = B_flat[2*M +: M];
            3'd4: prev_B = B_flat[3*M +: M];
            default: prev_B = {M{1'b0}};
        endcase
    end

    reg [M-1:0] current_syndrome;
    always @(*) begin
        current_syndrome = {M{1'b0}}; // Default assignment to prevent Latches
        if (r > k) begin
            case (r - k)
                5'd1: current_syndrome = syndromes[(1*M)-1 : 0*M];
                5'd2: current_syndrome = syndromes[(2*M)-1 : 1*M];
                5'd3: current_syndrome = syndromes[(3*M)-1 : 2*M];
                5'd4: current_syndrome = syndromes[(4*M)-1 : 3*M];
                5'd5: current_syndrome = syndromes[(5*M)-1 : 4*M];
                5'd6: current_syndrome = syndromes[(6*M)-1 : 5*M];
                5'd7: current_syndrome = syndromes[(7*M)-1 : 6*M];
                5'd8: current_syndrome = syndromes[(8*M)-1 : 7*M];
                default: current_syndrome = {M{1'b0}};
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // 4. ASIC Optimized Galois Field Multiplier Net
    // -------------------------------------------------------------------------
    wire [M-1:0] gf_mult_out = gf_mult(current_Lambda, current_syndrome);
    wire [M-1:0] lambda_update = gf_mult(gamma, current_Lambda) ^ gf_mult(delta_comb, prev_B);

    // -------------------------------------------------------------------------
    // 5. Dual-Path State Machine (Control Path)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            done          <= 1'b0;
            uncorrectable <= 1'b0;
            k             <= 3'd0;
            r             <= 5'd1;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        state <= CALC_DELTA;
                        k     <= 3'd0;
                        r     <= 5'd1;
                    end
                end

                CALC_DELTA: begin
                    if (k == T) begin
                        k     <= 3'd0;
                        state <= UPDATE;
                    end else begin
                        k     <= k + 1'b1;
                    end
                end

                UPDATE: begin
                    if (k == T) begin
                        k <= 3'd0;
                        if (r == 2 * T) begin
                            state <= IDLE;
                            done  <= 1'b1;
                            if ((update_B_flag ? (r - L) : L) > T)
                                uncorrectable <= 1'b1;
                            else
                                uncorrectable <= 1'b0;
                        end else begin
                            r     <= r + 1'b1;
                            state <= CALC_DELTA;
                        end
                    end else begin
                        k <= k + 1'b1;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // 6. Decoupled Data Path (Saves Area, Closed and Validated)
    // -------------------------------------------------------------------------
     always @(posedge clk) begin
        if (start && state == IDLE) begin
            Lambda_flat   <= {((T+1)*M){1'b0}} | 1'b1;
            B_flat        <= {((T+1)*M){1'b0}} | 1'b1;
            gamma         <= {M{1'b0}} | 1'b1;
            L             <= 5'd0;
            delta_comb    <= {M{1'b0}};
            update_B_flag <= 1'b0;
        end 
        else if (state == CALC_DELTA) begin
            delta_comb <= delta_comb ^ gf_mult_out;

            if (k == T) begin
                update_B_flag <= ((delta_comb ^ gf_mult_out) != {M{1'b0}}) && ({L, 1'b0} < {1'b0, r});
            end
            
            // Explicitly maintain state to prevent implicit DFFE/Latches
            Lambda_flat   <= Lambda_flat;
            B_flat        <= B_flat;
            gamma         <= gamma;
            L             <= L;
        end 
        else if (state == UPDATE) begin
            // We ensure every register gets an assignment in every branch,
            // preventing the inference of unmapped Clock-Enable Flip-Flops.
            gamma         <= (k == T && update_B_flag) ? delta_comb : gamma;
            L             <= (k == T && update_B_flag) ? (r - L) : L;
            delta_comb    <= (k == T) ? {M{1'b0}} : delta_comb;
            update_B_flag <= update_B_flag;

            case (k)
                3'd0: begin 
                    Lambda_flat[0*M +: M] <= lambda_update;
                    B_flat[0*M +: M]      <= update_B_flag ? current_Lambda : prev_B;
                end
                3'd1: begin 
                    Lambda_flat[1*M +: M] <= lambda_update;
                    B_flat[1*M +: M]      <= update_B_flag ? current_Lambda : prev_B;
                end
                3'd2: begin 
                    Lambda_flat[2*M +: M] <= lambda_update;
                    B_flat[2*M +: M]      <= update_B_flag ? current_Lambda : prev_B;
                end
                3'd3: begin 
                    Lambda_flat[3*M +: M] <= lambda_update;
                    B_flat[3*M +: M]      <= update_B_flag ? current_Lambda : prev_B;
                end
                3'd4: begin 
                    Lambda_flat[4*M +: M] <= lambda_update;
                    B_flat[4*M +: M]      <= update_B_flag ? current_Lambda : prev_B;
                end
                default: begin
                    Lambda_flat <= Lambda_flat;
                    B_flat      <= B_flat;
                end
            endcase
        end
        else begin
            // Safe fallback loop for IDLE or undefined states
            Lambda_flat   <= Lambda_flat;
            B_flat        <= B_flat;
            gamma         <= gamma;
            delta_comb    <= delta_comb;
            L             <= L;
            update_B_flag <= update_B_flag;
        end
    end

endmodule
