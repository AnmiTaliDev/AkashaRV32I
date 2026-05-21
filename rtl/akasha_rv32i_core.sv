// SPDX-FileCopyrightText: AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: CERN-OHL-S-2.0

// 5-stage in-order pipelined RV32I core: IF, ID, EX, MEM, WB.
// Data hazards resolved by full forwarding (EX/MEM and MEM/WB to EX) plus
// a one-cycle stall inserted for load-use hazards.
// Control hazards: branch and jump resolved at end of EX; the two slots
// fetched behind the redirecting instruction are flushed (2-cycle penalty).
// Memory stalls: imem_ready=0 freezes IF/ID; dmem_ready=0 freezes EX/MEM
// and all upstream stages.

module akasha_rv32i_core #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32
) (
    input  logic                    clk,
    input  logic                    rst_n,

    output logic [ADDR_WIDTH-1:0]   imem_addr,
    output logic                    imem_req,
    input  logic [DATA_WIDTH-1:0]   imem_rdata,
    input  logic                    imem_ready,

    output logic [ADDR_WIDTH-1:0]   dmem_addr,
    output logic [DATA_WIDTH-1:0]   dmem_wdata,
    output logic                    dmem_we,
    output logic [3:0]              dmem_be,
    output logic                    dmem_req,
    input  logic [DATA_WIDTH-1:0]   dmem_rdata,
    input  logic                    dmem_ready
);

    localparam logic [DATA_WIDTH-1:0] NOP_INSTR = 32'h00000013;

    // IF

    logic [ADDR_WIDTH-1:0] pc;
    assign imem_req  = 1'b1;
    assign imem_addr = pc;

    // IF/ID pipeline register

    logic [DATA_WIDTH-1:0] if_id_instr;
    logic [ADDR_WIDTH-1:0] if_id_pc;

    // ID decode

    logic [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;
    logic [2:0]  id_funct3;
    logic [6:0]  id_funct7, id_opcode;
    logic        id_reg_write, id_mem_read, id_mem_write;
    logic        id_branch, id_jump, id_jalr;
    logic        id_alu_src_imm, id_use_pc, id_lui_op, id_is_system;
    logic [3:0]  id_alu_op;
    logic [2:0]  id_imm_type;

    akasha_rv32i_decoder u_decoder (
        .instr          (if_id_instr),
        .rs1_addr       (id_rs1_addr),
        .rs2_addr       (id_rs2_addr),
        .rd_addr        (id_rd_addr),
        .funct3         (id_funct3),
        .funct7         (id_funct7),
        .opcode         (id_opcode),
        .reg_write      (id_reg_write),
        .mem_read       (id_mem_read),
        .mem_write      (id_mem_write),
        .branch         (id_branch),
        .jump           (id_jump),
        .jalr           (id_jalr),
        .alu_src_imm    (id_alu_src_imm),
        .use_pc_operand (id_use_pc),
        .lui_op         (id_lui_op),
        .is_system      (id_is_system),
        .alu_op         (id_alu_op),
        .imm_type       (id_imm_type)
    );

    logic [DATA_WIDTH-1:0] id_imm;

    akasha_rv32i_imm_gen u_imm_gen (
        .instr    (if_id_instr),
        .imm_type (id_imm_type),
        .imm      (id_imm)
    );

    // WB write-port signals (driven from MEM/WB register below).
    logic [DATA_WIDTH-1:0] wb_wdata;
    logic [4:0]            wb_rd_addr;
    logic                  wb_reg_write;

    logic [DATA_WIDTH-1:0] id_rs1_data, id_rs2_data;

    akasha_rv32i_regfile #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_regfile (
        .clk      (clk),
        .rst_n    (rst_n),
        .we       (wb_reg_write),
        .rd_addr  (wb_rd_addr),
        .rd_wdata (wb_wdata),
        .rs1_addr (id_rs1_addr),
        .rs2_addr (id_rs2_addr),
        .rs1_data (id_rs1_data),
        .rs2_data (id_rs2_data)
    );

    // Hazard detection: load-use stall.
    // ex_mem_read and ex_rd_addr are aliases into the ID/EX register below.

    logic        ex_mem_read;
    logic [4:0]  ex_rd_addr;

    logic load_use_stall;
    assign load_use_stall = ex_mem_read && (ex_rd_addr != 5'd0) &&
                            ((ex_rd_addr == id_rs1_addr) ||
                             (ex_rd_addr == id_rs2_addr));

    logic stall;
    assign stall = load_use_stall | ~imem_ready;

    // ID/EX pipeline register

    logic [DATA_WIDTH-1:0] ex_rs1_data, ex_rs2_data, ex_imm;
    logic [ADDR_WIDTH-1:0] ex_pc;
    logic [4:0]            ex_rs1_addr, ex_rs2_addr;
    logic [2:0]            ex_funct3;
    logic                  ex_reg_write, ex_mem_write;
    logic                  ex_branch, ex_jump, ex_jalr;
    logic                  ex_alu_src_imm, ex_use_pc, ex_lui_op;
    logic [3:0]            ex_alu_op;

    // Forwarding taps for EX/MEM and MEM/WB stages.
    logic [DATA_WIDTH-1:0] exmem_fwd, memwb_fwd;
    logic [4:0]            exmem_rd,  memwb_rd;
    logic                  exmem_we,  memwb_we;

    // EX forwarding muxes.
    logic [1:0] fwd_a, fwd_b;

    always_comb begin
        fwd_a = 2'b00;
        if (exmem_we && (exmem_rd != 5'd0) && (exmem_rd == ex_rs1_addr))
            fwd_a = 2'b10;
        else if (memwb_we && (memwb_rd != 5'd0) && (memwb_rd == ex_rs1_addr))
            fwd_a = 2'b01;
    end

    always_comb begin
        fwd_b = 2'b00;
        if (exmem_we && (exmem_rd != 5'd0) && (exmem_rd == ex_rs2_addr))
            fwd_b = 2'b10;
        else if (memwb_we && (memwb_rd != 5'd0) && (memwb_rd == ex_rs2_addr))
            fwd_b = 2'b01;
    end

    logic [DATA_WIDTH-1:0] ex_rs1_fwd, ex_rs2_fwd;

    always_comb begin
        unique case (fwd_a)
            2'b10:   ex_rs1_fwd = exmem_fwd;
            2'b01:   ex_rs1_fwd = memwb_fwd;
            default: ex_rs1_fwd = ex_rs1_data;
        endcase
    end

    always_comb begin
        unique case (fwd_b)
            2'b10:   ex_rs2_fwd = exmem_fwd;
            2'b01:   ex_rs2_fwd = memwb_fwd;
            default: ex_rs2_fwd = ex_rs2_data;
        endcase
    end

    logic [DATA_WIDTH-1:0] alu_a, alu_b;
    assign alu_a = ex_use_pc      ? ex_pc  : ex_rs1_fwd;
    assign alu_b = ex_alu_src_imm ? ex_imm : ex_rs2_fwd;

    logic [DATA_WIDTH-1:0] alu_result;
    logic                  alu_zero, alu_lt, alu_ltu;

    akasha_rv32i_alu #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_alu (
        .alu_op      (ex_alu_op),
        .operand_a   (alu_a),
        .operand_b   (alu_b),
        .result      (alu_result),
        .zero        (alu_zero),
        .less_than   (alu_lt),
        .less_than_u (alu_ltu)
    );

    logic ex_branch_taken;
    always_comb begin
        ex_branch_taken = 1'b0;
        if (ex_branch) begin
            unique case (ex_funct3)
                3'b000:  ex_branch_taken = alu_zero;
                3'b001:  ex_branch_taken = ~alu_zero;
                3'b100:  ex_branch_taken = alu_lt;
                3'b101:  ex_branch_taken = ~alu_lt;
                3'b110:  ex_branch_taken = alu_ltu;
                3'b111:  ex_branch_taken = ~alu_ltu;
                default: ex_branch_taken = 1'b0;
            endcase
        end
    end

    logic                  ex_redirect;
    logic [ADDR_WIDTH-1:0] ex_target;

    assign ex_redirect = ex_jump | ex_jalr | ex_branch_taken;

    always_comb begin
        if (ex_jalr)
            ex_target = (ex_rs1_fwd + ex_imm) & {{ADDR_WIDTH-1{1'b1}}, 1'b0};
        else
            ex_target = ex_pc + ex_imm;
    end

    // EX writeback data: loads get real data after MEM; use alu_result as placeholder.
    logic [DATA_WIDTH-1:0] ex_wdata;
    always_comb begin
        if (ex_jump | ex_jalr)
            ex_wdata = ex_pc + 32'd4;
        else if (ex_lui_op)
            ex_wdata = ex_imm;
        else
            ex_wdata = alu_result;
    end

    // EX/MEM pipeline register

    logic [DATA_WIDTH-1:0] mem_alu_result, mem_rs2_data, mem_wdata;
    logic [4:0]            mem_rd_addr;
    logic [2:0]            mem_funct3;
    logic                  mem_reg_write, mem_mem_read, mem_mem_write;

    logic dmem_stall;
    assign dmem_stall = (mem_mem_read | mem_mem_write) & ~dmem_ready;

    // MEM load/store

    logic [DATA_WIDTH-1:0] mem_load_data;

    akasha_rv32i_lsu #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_lsu (
        .mem_read   (mem_mem_read),
        .mem_write  (mem_mem_write),
        .funct3     (mem_funct3),
        .addr       (mem_alu_result),
        .store_data (mem_rs2_data),
        .dmem_rdata (dmem_rdata),
        .dmem_addr  (dmem_addr),
        .dmem_wdata (dmem_wdata),
        .dmem_we    (dmem_we),
        .dmem_be    (dmem_be),
        .load_data  (mem_load_data)
    );

    assign dmem_req = mem_mem_read | mem_mem_write;

    // Pipeline flush/stall control.
    // Redirect flushes the two slots already in IF and ID behind the branch/jump.
    // load_use_stall squashes the slot in EX (the bubble) and holds IF/ID.

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc <= '0;
        else if (ex_redirect)
            pc <= ex_target;
        else if (~stall & ~dmem_stall)
            pc <= pc + 32'd4;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_instr <= NOP_INSTR;
            if_id_pc    <= '0;
        end else if (ex_redirect) begin
            if_id_instr <= NOP_INSTR;
            if_id_pc    <= '0;
        end else if (~stall & ~dmem_stall) begin
            if_id_instr <= imem_rdata;
            if_id_pc    <= pc;
        end
    end

    // ID/EX latch.
    // Flush (ex_redirect, load_use_stall) takes priority over dmem_stall.
    // When only dmem_stall is asserted the slot must be held, not squashed,
    // so the instruction waiting in ID does not get lost.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || ex_redirect || load_use_stall) begin
            ex_rs1_data    <= '0;
            ex_rs2_data    <= '0;
            ex_imm         <= '0;
            ex_pc          <= '0;
            ex_rs1_addr    <= '0;
            ex_rs2_addr    <= '0;
            ex_rd_addr     <= '0;
            ex_funct3      <= '0;
            ex_reg_write   <= '0;
            ex_mem_read    <= '0;
            ex_mem_write   <= '0;
            ex_branch      <= '0;
            ex_jump        <= '0;
            ex_jalr        <= '0;
            ex_alu_src_imm <= '0;
            ex_use_pc      <= '0;
            ex_lui_op      <= '0;
            ex_alu_op      <= '0;
        end else if (~dmem_stall) begin
            ex_rs1_data    <= id_rs1_data;
            ex_rs2_data    <= id_rs2_data;
            ex_imm         <= id_imm;
            ex_pc          <= if_id_pc;
            ex_rs1_addr    <= id_rs1_addr;
            ex_rs2_addr    <= id_rs2_addr;
            ex_rd_addr     <= id_rd_addr;
            ex_funct3      <= id_funct3;
            ex_reg_write   <= id_reg_write;
            ex_mem_read    <= id_mem_read;
            ex_mem_write   <= id_mem_write;
            ex_branch      <= id_branch;
            ex_jump        <= id_jump;
            ex_jalr        <= id_jalr;
            ex_alu_src_imm <= id_alu_src_imm;
            ex_use_pc      <= id_use_pc;
            ex_lui_op      <= id_lui_op;
            ex_alu_op      <= id_alu_op;
        end
        // dmem_stall without flush: hold current value implicitly.
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_alu_result <= '0;
            mem_wdata      <= '0;
            mem_rs2_data   <= '0;
            mem_rd_addr    <= '0;
            mem_funct3     <= '0;
            mem_reg_write  <= '0;
            mem_mem_read   <= '0;
            mem_mem_write  <= '0;
        end else if (~dmem_stall) begin
            mem_alu_result <= alu_result;
            mem_wdata      <= ex_wdata;
            mem_rs2_data   <= ex_rs2_fwd;
            mem_rd_addr    <= ex_rd_addr;
            mem_funct3     <= ex_funct3;
            mem_reg_write  <= ex_reg_write;
            mem_mem_read   <= ex_mem_read;
            mem_mem_write  <= ex_mem_write;
        end
    end

    // EX/MEM forwarding tap.
    assign exmem_fwd = mem_wdata;
    assign exmem_rd  = mem_rd_addr;
    assign exmem_we  = mem_reg_write;

    // MEM/WB pipeline register and WB logic.

    // MEM/WB latch.
    // Must be held during dmem_stall: mem_load_data is not yet valid and
    // capturing it would corrupt the destination register.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_wdata     <= '0;
            wb_rd_addr   <= '0;
            wb_reg_write <= '0;
        end else if (~dmem_stall) begin
            wb_wdata     <= mem_mem_read ? mem_load_data : mem_wdata;
            wb_rd_addr   <= mem_rd_addr;
            wb_reg_write <= mem_reg_write;
        end
        // dmem_stall: hold — the previous instruction's writeback stays
        // in place; writing it again on the next cycle is idempotent.
    end

    // MEM/WB forwarding tap.
    assign memwb_fwd = wb_wdata;
    assign memwb_rd  = wb_rd_addr;
    assign memwb_we  = wb_reg_write;

endmodule
