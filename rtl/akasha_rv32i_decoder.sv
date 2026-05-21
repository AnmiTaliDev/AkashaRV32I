// SPDX-FileCopyrightText: AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: CERN-OHL-S-2.0

// Instruction decoder for RV32I.
// Splits the instruction word into fields and produces the control signals
// that steer datapath multiplexers, the register file and memory ports.

module akasha_rv32i_decoder (
    input  logic [31:0] instr,

    output logic [4:0]  rs1_addr,
    output logic [4:0]  rs2_addr,
    output logic [4:0]  rd_addr,
    output logic [2:0]  funct3,
    output logic [6:0]  funct7,
    output logic [6:0]  opcode,

    output logic        reg_write,
    output logic        mem_read,
    output logic        mem_write,
    output logic        branch,
    output logic        jump,
    output logic        jalr,
    output logic        alu_src_imm,
    output logic        use_pc_operand,
    output logic        lui_op,
    output logic        is_system,
    output logic [3:0]  alu_op,
    output logic [2:0]  imm_type
);

    // Opcode encodings.
    localparam logic [6:0] OP_LUI    = 7'b0110111;
    localparam logic [6:0] OP_AUIPC  = 7'b0010111;
    localparam logic [6:0] OP_JAL    = 7'b1101111;
    localparam logic [6:0] OP_JALR   = 7'b1100111;
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_LOAD   = 7'b0000011;
    localparam logic [6:0] OP_STORE  = 7'b0100011;
    localparam logic [6:0] OP_IMM    = 7'b0010011;
    localparam logic [6:0] OP_REG    = 7'b0110011;
    localparam logic [6:0] OP_FENCE  = 7'b0001111;
    localparam logic [6:0] OP_SYSTEM = 7'b1110011;

    // Immediate type selectors shared with the immediate generator.
    localparam logic [2:0] IMM_I = 3'b000;
    localparam logic [2:0] IMM_S = 3'b001;
    localparam logic [2:0] IMM_B = 3'b010;
    localparam logic [2:0] IMM_U = 3'b011;
    localparam logic [2:0] IMM_J = 3'b100;

    // ALU operation encodings shared with the ALU.
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

    assign opcode   = instr[6:0];
    assign rd_addr  = instr[11:7];
    assign funct3   = instr[14:12];
    assign rs1_addr = instr[19:15];
    assign rs2_addr = instr[24:20];
    assign funct7   = instr[31:25];

    // Control decode.
    always_comb begin
        reg_write      = 1'b0;
        mem_read       = 1'b0;
        mem_write      = 1'b0;
        branch         = 1'b0;
        jump           = 1'b0;
        jalr           = 1'b0;
        alu_src_imm    = 1'b0;
        use_pc_operand = 1'b0;
        lui_op         = 1'b0;
        is_system      = 1'b0;
        imm_type       = IMM_I;

        unique case (opcode)
            OP_LUI: begin
                reg_write   = 1'b1;
                alu_src_imm = 1'b1;
                lui_op      = 1'b1;
                imm_type    = IMM_U;
            end
            OP_AUIPC: begin
                reg_write      = 1'b1;
                alu_src_imm    = 1'b1;
                use_pc_operand = 1'b1;
                imm_type       = IMM_U;
            end
            OP_JAL: begin
                reg_write = 1'b1;
                jump      = 1'b1;
                imm_type  = IMM_J;
            end
            OP_JALR: begin
                reg_write   = 1'b1;
                jalr        = 1'b1;
                alu_src_imm = 1'b1;
                imm_type    = IMM_I;
            end
            OP_BRANCH: begin
                branch   = 1'b1;
                imm_type = IMM_B;
            end
            OP_LOAD: begin
                reg_write   = 1'b1;
                mem_read    = 1'b1;
                alu_src_imm = 1'b1;
                imm_type    = IMM_I;
            end
            OP_STORE: begin
                mem_write   = 1'b1;
                alu_src_imm = 1'b1;
                imm_type    = IMM_S;
            end
            OP_IMM: begin
                reg_write   = 1'b1;
                alu_src_imm = 1'b1;
                imm_type    = IMM_I;
            end
            OP_REG: begin
                reg_write = 1'b1;
            end
            OP_FENCE: begin
                // Memory ordering is implicit on this in-order core with a
                // single outstanding access, so FENCE retires as a no-op.
            end
            OP_SYSTEM: begin
                is_system = 1'b1;
            end
            default: begin
                // Unsupported opcode behaves as a no-operation.
            end
        endcase
    end

    // ALU operation decode.
    logic [3:0] alu_op_reg;
    logic [3:0] alu_op_imm;

    always_comb begin
        unique case (funct3)
            3'b000:  alu_op_reg = funct7[5] ? ALU_SUB : ALU_ADD;
            3'b001:  alu_op_reg = ALU_SLL;
            3'b010:  alu_op_reg = ALU_SLT;
            3'b011:  alu_op_reg = ALU_SLTU;
            3'b100:  alu_op_reg = ALU_XOR;
            3'b101:  alu_op_reg = funct7[5] ? ALU_SRA : ALU_SRL;
            3'b110:  alu_op_reg = ALU_OR;
            3'b111:  alu_op_reg = ALU_AND;
            default: alu_op_reg = ALU_ADD;
        endcase
    end

    // Immediate ALU ops match register ops, except that only the shift-right
    // form inspects bit 30 to choose between logical and arithmetic shifts.
    always_comb begin
        unique case (funct3)
            3'b000:  alu_op_imm = ALU_ADD;
            3'b001:  alu_op_imm = ALU_SLL;
            3'b010:  alu_op_imm = ALU_SLT;
            3'b011:  alu_op_imm = ALU_SLTU;
            3'b100:  alu_op_imm = ALU_XOR;
            3'b101:  alu_op_imm = funct7[5] ? ALU_SRA : ALU_SRL;
            3'b110:  alu_op_imm = ALU_OR;
            3'b111:  alu_op_imm = ALU_AND;
            default: alu_op_imm = ALU_ADD;
        endcase
    end

    always_comb begin
        unique case (opcode)
            OP_REG:  alu_op = alu_op_reg;
            OP_IMM:  alu_op = alu_op_imm;
            default: alu_op = ALU_ADD;
        endcase
    end

endmodule
