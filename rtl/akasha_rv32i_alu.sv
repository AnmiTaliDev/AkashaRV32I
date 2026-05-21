// SPDX-FileCopyrightText: AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: CERN-OHL-S-2.0

// Arithmetic logic unit for RV32I.
// Computes the result for arithmetic, logic, shift and comparison operations
// and exposes flags used by branch resolution.

module akasha_rv32i_alu #(
    parameter int DATA_WIDTH = 32
) (
    input  logic [3:0]            alu_op,
    input  logic [DATA_WIDTH-1:0] operand_a,
    input  logic [DATA_WIDTH-1:0] operand_b,
    output logic [DATA_WIDTH-1:0] result,
    output logic                  zero,
    output logic                  less_than,
    output logic                  less_than_u
);

    // ALU operation encodings shared with the decoder.
    localparam logic [3:0] ALU_ADD  = 4'b0000;
    localparam logic [3:0] ALU_SUB  = 4'b0001;
    localparam logic [3:0] ALU_SLL  = 4'b0010;
    localparam logic [3:0] ALU_SLT  = 4'b0011;
    localparam logic [3:0] ALU_SLTU = 4'b0100;
    localparam logic [3:0] ALU_XOR  = 4'b0101;
    localparam logic [3:0] ALU_SRL  = 4'b0110;
    localparam logic [3:0] ALU_SRA  = 4'b0111;
    localparam logic [3:0] ALU_OR   = 4'b1000;
    localparam logic [3:0] ALU_AND  = 4'b1001;

    logic [4:0] shamt;
    assign shamt = operand_b[4:0];

    logic signed_lt;
    logic unsigned_lt;
    assign signed_lt   = $signed(operand_a) < $signed(operand_b);
    assign unsigned_lt = operand_a < operand_b;

    always_comb begin
        unique case (alu_op)
            ALU_ADD:  result = operand_a + operand_b;
            ALU_SUB:  result = operand_a - operand_b;
            ALU_SLL:  result = operand_a << shamt;
            ALU_SLT:  result = {{DATA_WIDTH-1{1'b0}}, signed_lt};
            ALU_SLTU: result = {{DATA_WIDTH-1{1'b0}}, unsigned_lt};
            ALU_XOR:  result = operand_a ^ operand_b;
            ALU_SRL:  result = operand_a >> shamt;
            ALU_SRA:  result = $signed(operand_a) >>> shamt;
            ALU_OR:   result = operand_a | operand_b;
            ALU_AND:  result = operand_a & operand_b;
            default:  result = '0;
        endcase
    end

    assign zero        = (operand_a == operand_b);
    assign less_than   = signed_lt;
    assign less_than_u = unsigned_lt;

endmodule
