// SPDX-FileCopyrightText: AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: CERN-OHL-S-2.0

// Basic testbench for the AkashaRV32I core.
// Provides zero wait state instruction and data memory models and runs a small
// program that exercises arithmetic, load/store, branch and jump paths, then
// checks the resulting register values.

`timescale 1ns / 1ps

module akasha_rv32i_core_tb;

    localparam int DATA_WIDTH = 32;
    localparam int ADDR_WIDTH = 32;
    localparam int IMEM_WORDS = 256;
    localparam int DMEM_WORDS = 256;
    localparam int MAX_CYCLES = 200;

    logic                    clk;
    logic                    rst_n;

    logic [ADDR_WIDTH-1:0]   imem_addr;
    logic                    imem_req;
    logic [DATA_WIDTH-1:0]   imem_rdata;
    logic                    imem_ready;

    logic [ADDR_WIDTH-1:0]   dmem_addr;
    logic [DATA_WIDTH-1:0]   dmem_wdata;
    logic                    dmem_we;
    logic [3:0]              dmem_be;
    logic                    dmem_req;
    logic [DATA_WIDTH-1:0]   dmem_rdata;
    logic                    dmem_ready;

    akasha_rv32i_core #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .imem_addr  (imem_addr),
        .imem_req   (imem_req),
        .imem_rdata (imem_rdata),
        .imem_ready (imem_ready),
        .dmem_addr  (dmem_addr),
        .dmem_wdata (dmem_wdata),
        .dmem_we    (dmem_we),
        .dmem_be    (dmem_be),
        .dmem_req   (dmem_req),
        .dmem_rdata (dmem_rdata),
        .dmem_ready (dmem_ready)
    );

    // Memory models.
    localparam int IMEM_IDX_W = $clog2(IMEM_WORDS);
    localparam int DMEM_IDX_W = $clog2(DMEM_WORDS);

    logic [DATA_WIDTH-1:0] imem [0:IMEM_WORDS-1];
    logic [DATA_WIDTH-1:0] dmem [0:DMEM_WORDS-1];

    // Word index into each memory derived from the byte address.
    logic [IMEM_IDX_W-1:0] imem_index;
    logic [DMEM_IDX_W-1:0] dmem_index;
    assign imem_index = imem_addr[IMEM_IDX_W+1:2];
    assign dmem_index = dmem_addr[DMEM_IDX_W+1:2];

    // Zero wait state instruction read.
    assign imem_ready = 1'b1;
    assign imem_rdata = imem[imem_index];

    // Zero wait state data read.
    assign dmem_ready = 1'b1;
    assign dmem_rdata = dmem[dmem_index];

    // Data write with byte enables.
    always_ff @(posedge clk) begin
        if (dmem_req && dmem_we) begin
            if (dmem_be[0]) dmem[dmem_index][7:0]   <= dmem_wdata[7:0];
            if (dmem_be[1]) dmem[dmem_index][15:8]  <= dmem_wdata[15:8];
            if (dmem_be[2]) dmem[dmem_index][23:16] <= dmem_wdata[23:16];
            if (dmem_be[3]) dmem[dmem_index][31:24] <= dmem_wdata[31:24];
        end
    end

    // Clock generation.
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Instruction encoding helpers.
    function automatic logic [31:0] r_type(
        input logic [6:0] f7, input logic [4:0] rs2, input logic [4:0] rs1,
        input logic [2:0] f3, input logic [4:0] rd, input logic [6:0] op);
        return {f7, rs2, rs1, f3, rd, op};
    endfunction

    function automatic logic [31:0] i_type(
        input logic [11:0] imm, input logic [4:0] rs1,
        input logic [2:0] f3, input logic [4:0] rd, input logic [6:0] op);
        return {imm, rs1, f3, rd, op};
    endfunction

    function automatic logic [31:0] s_type(
        input logic [11:0] imm, input logic [4:0] rs2, input logic [4:0] rs1,
        input logic [2:0] f3, input logic [6:0] op);
        return {imm[11:5], rs2, rs1, f3, imm[4:0], op};
    endfunction

    function automatic logic [31:0] b_type(
        input logic [12:0] imm, input logic [4:0] rs2, input logic [4:0] rs1,
        input logic [2:0] f3, input logic [6:0] op);
        return {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], op};
    endfunction

    function automatic logic [31:0] u_type(
        input logic [19:0] imm, input logic [4:0] rd, input logic [6:0] op);
        return {imm, rd, op};
    endfunction

    function automatic logic [31:0] j_type(
        input logic [20:0] imm, input logic [4:0] rd, input logic [6:0] op);
        return {imm[20], imm[10:1], imm[11], imm[19:12], rd, op};
    endfunction

    // Opcodes.
    localparam logic [6:0] OP_LUI    = 7'b0110111;
    localparam logic [6:0] OP_AUIPC  = 7'b0010111;
    localparam logic [6:0] OP_JAL    = 7'b1101111;
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_LOAD   = 7'b0000011;
    localparam logic [6:0] OP_STORE  = 7'b0100011;
    localparam logic [6:0] OP_IMM    = 7'b0010011;
    localparam logic [6:0] OP_REG    = 7'b0110011;

    // Selected funct3 and funct7 values.
    localparam logic [2:0] F3_ADD  = 3'b000;
    localparam logic [2:0] F3_BEQ  = 3'b000;
    localparam logic [2:0] F3_SLTU = 3'b011;
    localparam logic [2:0] F3_W    = 3'b010;
    localparam logic [6:0] F7_ZERO = 7'b0000000;
    localparam logic [6:0] F7_SUB  = 7'b0100000;

    integer errors;

    task automatic check_reg(input [4:0] idx, input logic [31:0] expected);
        logic [31:0] actual;
        actual = dut.u_regfile.registers[idx];
        if (actual !== expected) begin
            errors = errors + 1;
            $display("FAIL x%0d = 0x%08h, expected 0x%08h", idx, actual, expected);
        end else begin
            $display("PASS x%0d = 0x%08h", idx, actual);
        end
    endtask

    integer k;

    initial begin
        errors = 0;

        for (k = 0; k < IMEM_WORDS; k = k + 1) imem[k] = 32'h00000013; // NOP (ADDI x0,x0,0)
        for (k = 0; k < DMEM_WORDS; k = k + 1) dmem[k] = 32'h00000000;

        // Test program. Word index equals byte address divided by four.
        imem[0]  = i_type(12'd5,    5'd0, F3_ADD, 5'd1,  OP_IMM);    // ADDI x1, x0, 5
        imem[1]  = i_type(12'd10,   5'd0, F3_ADD, 5'd2,  OP_IMM);    // ADDI x2, x0, 10
        imem[2]  = r_type(F7_ZERO, 5'd2, 5'd1, F3_ADD, 5'd3, OP_REG);// ADD  x3, x1, x2
        imem[3]  = r_type(F7_SUB,  5'd1, 5'd2, F3_ADD, 5'd4, OP_REG);// SUB  x4, x2, x1
        imem[4]  = s_type(12'd0,   5'd3, 5'd0, F3_W, OP_STORE);      // SW   x3, 0(x0)
        imem[5]  = i_type(12'd0,   5'd0, F3_W, 5'd5,  OP_LOAD);      // LW   x5, 0(x0)
        imem[6]  = b_type(13'd8,   5'd5, 5'd3, F3_BEQ, OP_BRANCH);   // BEQ  x3, x5, +8
        imem[7]  = i_type(12'hFF,  5'd0, F3_ADD, 5'd6,  OP_IMM);     // ADDI x6, x0, 255 (skipped)
        imem[8]  = j_type(21'd8,   5'd7, OP_JAL);                    // JAL  x7, +8
        imem[9]  = i_type(12'hAA,  5'd0, F3_ADD, 5'd8,  OP_IMM);     // ADDI x8, x0, 170 (skipped)
        imem[10] = i_type(12'd99,  5'd0, F3_ADD, 5'd9,  OP_IMM);     // ADDI x9, x0, 99
        imem[11] = u_type(20'h12345, 5'd10, OP_LUI);                 // LUI  x10, 0x12345
        imem[12] = u_type(20'd0,   5'd11, OP_AUIPC);                 // AUIPC x11, 0
        imem[13] = i_type(12'hFFF,  5'd1, F3_SLTU, 5'd12, OP_IMM);   // SLTIU x12, x1, -1 -> 1
        imem[14] = 32'h0000000f;                                     // FENCE (retires as no-op)
        imem[15] = i_type(12'd7,   5'd0, F3_ADD, 5'd13, OP_IMM);     // ADDI x13, x0, 7 (runs after FENCE)
        imem[16] = j_type(21'd0,   5'd0, OP_JAL);                    // JAL  x0, 0 (halt loop)

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (MAX_CYCLES) @(posedge clk);

        $display("AkashaRV32I core testbench");
        check_reg(5'd1,  32'd5);
        check_reg(5'd2,  32'd10);
        check_reg(5'd3,  32'd15);
        check_reg(5'd4,  32'd5);
        check_reg(5'd5,  32'd15);
        check_reg(5'd6,  32'd0);            // branch skipped the write
        check_reg(5'd7,  32'h00000024);     // JAL link address
        check_reg(5'd8,  32'd0);            // jump skipped the write
        check_reg(5'd9,  32'd99);
        check_reg(5'd10, 32'h12345000);
        check_reg(5'd11, 32'h00000030);     // AUIPC at byte address 0x30
        check_reg(5'd12, 32'h00000001);     // SLTIU x1(5) < -1 unsigned -> 1
        check_reg(5'd13, 32'h00000007);     // ADDI after FENCE proves FENCE is a no-op

        if (dmem[0] !== 32'd15) begin
            errors = errors + 1;
            $display("FAIL dmem[0] = 0x%08h, expected 0x0000000f", dmem[0]);
        end else begin
            $display("PASS dmem[0] = 0x%08h", dmem[0]);
        end

        if (errors == 0)
            $display("RESULT: all checks passed");
        else
            $display("RESULT: %0d check(s) failed", errors);

        $finish;
    end

endmodule
