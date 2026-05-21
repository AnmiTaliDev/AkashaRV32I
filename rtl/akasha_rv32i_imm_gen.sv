// SPDX-FileCopyrightText: AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: CERN-OHL-S-2.0

// Immediate generator for RV32I.
// Reconstructs and sign extends the immediate field according to the
// instruction format selected by the decoder.

module akasha_rv32i_imm_gen (
    input  logic [31:0] instr,
    input  logic [2:0]  imm_type,
    output logic [31:0] imm
);

    localparam logic [2:0] IMM_I = 3'b000;
    localparam logic [2:0] IMM_S = 3'b001;
    localparam logic [2:0] IMM_B = 3'b010;
    localparam logic [2:0] IMM_U = 3'b011;
    localparam logic [2:0] IMM_J = 3'b100;

    logic [31:0] imm_i;
    logic [31:0] imm_s;
    logic [31:0] imm_b;
    logic [31:0] imm_u;
    logic [31:0] imm_j;

    assign imm_i = {{20{instr[31]}}, instr[31:20]};
    assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    assign imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    assign imm_u = {instr[31:12], 12'b0};
    assign imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    always_comb begin
        unique case (imm_type)
            IMM_I:   imm = imm_i;
            IMM_S:   imm = imm_s;
            IMM_B:   imm = imm_b;
            IMM_U:   imm = imm_u;
            IMM_J:   imm = imm_j;
            default: imm = imm_i;
        endcase
    end

endmodule
