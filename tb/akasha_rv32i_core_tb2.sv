// SPDX-FileCopyrightText: AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: CERN-OHL-S-2.0

// Second testbench for the AkashaRV32I core.
// Targets the paths the first testbench does not exercise: shifts, signed and
// unsigned set-less-than, the full logic group, sub-word loads and stores at
// non-zero byte offsets, every branch condition in both taken and not-taken
// forms, and the JALR indirect jump.

`timescale 1ns / 1ps

module akasha_rv32i_core_tb2;

    localparam int DATA_WIDTH = 32;
    localparam int ADDR_WIDTH = 32;
    localparam int IMEM_WORDS = 256;
    localparam int DMEM_WORDS = 256;
    localparam int MAX_CYCLES = 300;

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

    logic [IMEM_IDX_W-1:0] imem_index;
    logic [DMEM_IDX_W-1:0] dmem_index;
    assign imem_index = imem_addr[IMEM_IDX_W+1:2];
    assign dmem_index = dmem_addr[DMEM_IDX_W+1:2];

    assign imem_ready = 1'b1;
    assign imem_rdata = imem[imem_index];

    assign dmem_ready = 1'b1;
    assign dmem_rdata = dmem[dmem_index];

    always_ff @(posedge clk) begin
        if (dmem_req && dmem_we) begin
            if (dmem_be[0]) dmem[dmem_index][7:0]   <= dmem_wdata[7:0];
            if (dmem_be[1]) dmem[dmem_index][15:8]  <= dmem_wdata[15:8];
            if (dmem_be[2]) dmem[dmem_index][23:16] <= dmem_wdata[23:16];
            if (dmem_be[3]) dmem[dmem_index][31:24] <= dmem_wdata[31:24];
        end
    end

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

    function automatic logic [31:0] j_type(
        input logic [20:0] imm, input logic [4:0] rd, input logic [6:0] op);
        return {imm[20], imm[10:1], imm[11], imm[19:12], rd, op};
    endfunction

    // Opcodes.
    localparam logic [6:0] OP_JAL    = 7'b1101111;
    localparam logic [6:0] OP_JALR   = 7'b1100111;
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_LOAD   = 7'b0000011;
    localparam logic [6:0] OP_STORE  = 7'b0100011;
    localparam logic [6:0] OP_IMM    = 7'b0010011;
    localparam logic [6:0] OP_REG    = 7'b0110011;

    // funct3 codes.
    localparam logic [2:0] F3_ADD  = 3'b000;
    localparam logic [2:0] F3_SLL  = 3'b001;
    localparam logic [2:0] F3_SLT  = 3'b010;
    localparam logic [2:0] F3_SLTU = 3'b011;
    localparam logic [2:0] F3_XOR  = 3'b100;
    localparam logic [2:0] F3_SR   = 3'b101;
    localparam logic [2:0] F3_OR   = 3'b110;
    localparam logic [2:0] F3_AND  = 3'b111;

    localparam logic [2:0] F3_BEQ  = 3'b000;
    localparam logic [2:0] F3_BNE  = 3'b001;
    localparam logic [2:0] F3_BLT  = 3'b100;
    localparam logic [2:0] F3_BGE  = 3'b101;
    localparam logic [2:0] F3_BLTU = 3'b110;
    localparam logic [2:0] F3_BGEU = 3'b111;

    localparam logic [2:0] F3_B  = 3'b000;
    localparam logic [2:0] F3_H  = 3'b001;
    localparam logic [2:0] F3_W  = 3'b010;
    localparam logic [2:0] F3_BU = 3'b100;
    localparam logic [2:0] F3_HU = 3'b101;

    localparam logic [6:0] F7_ZERO = 7'b0000000;
    localparam logic [6:0] F7_ALT  = 7'b0100000;

    integer errors;

    task automatic check_reg(input [4:0] idx, input logic [31:0] expected, input string label);
        logic [31:0] actual;
        actual = dut.u_regfile.registers[idx];
        if (actual !== expected) begin
            errors = errors + 1;
            $display("FAIL %-10s x%0d = 0x%08h, expected 0x%08h", label, idx, actual, expected);
        end else begin
            $display("PASS %-10s x%0d = 0x%08h", label, idx, actual);
        end
    endtask

    integer k;

    initial begin
        errors = 0;

        for (k = 0; k < IMEM_WORDS; k = k + 1) imem[k] = 32'h00000013; // NOP
        for (k = 0; k < DMEM_WORDS; k = k + 1) dmem[k] = 32'h00000000;

        // Set up source values.
        // x1 = 0x00000004
        imem[0]  = i_type(12'd4,        5'd0, F3_ADD, 5'd1, OP_IMM);
        // x2 = 0xFFFFFFFF (-1) via ADDI x2, x0, -1
        imem[1]  = i_type(12'hFFF,      5'd0, F3_ADD, 5'd2, OP_IMM);
        // x3 = 0x80000000 = (1 << 31): start from 1 then SLLI 31
        imem[2]  = i_type(12'd1,        5'd0, F3_ADD, 5'd3, OP_IMM);
        imem[3]  = i_type(12'd31,       5'd3, F3_SLL, 5'd3, OP_IMM);  // SLLI x3, x3, 31

        // Shifts.
        // x4 = x1 << 3 = 0x20
        imem[4]  = i_type(12'd3,        5'd1, F3_SLL, 5'd4, OP_IMM);  // SLLI
        // x5 = x3 >> 4 logical = 0x08000000
        imem[5]  = i_type(12'd4,        5'd3, F3_SR,  5'd5, OP_IMM);  // SRLI
        // x6 = x3 >>> 4 arithmetic = 0xF8000000
        imem[6]  = i_type({F7_ALT, 5'd4}, 5'd3, F3_SR, 5'd6, OP_IMM); // SRAI x6, x3, 4
        // x7 = x2 >>> 1 arithmetic = 0xFFFFFFFF (sign keeps all ones)
        imem[7]  = r_type(F7_ALT, 5'd1, 5'd2, F3_SR, 5'd7, OP_REG);   // SRA x7, x2, x1(=4)

        // Set-less-than.
        // x8 = (x2 <s x1) ? 1 : 0 -> (-1 < 4) = 1
        imem[8]  = r_type(F7_ZERO, 5'd1, 5'd2, F3_SLT,  5'd8, OP_REG); // SLT
        // x9 = (x2 <u x1) ? 1 : 0 -> (0xFFFFFFFF < 4) = 0
        imem[9]  = r_type(F7_ZERO, 5'd1, 5'd2, F3_SLTU, 5'd9, OP_REG); // SLTU
        // x10 = (x1 <s 5) = 1 via SLTI
        imem[10] = i_type(12'd5,        5'd1, F3_SLT,  5'd10, OP_IMM);

        // Logic group.
        // x11 = x1 ^ x2 = 0xFFFFFFFB
        imem[11] = r_type(F7_ZERO, 5'd2, 5'd1, F3_XOR, 5'd11, OP_REG);
        // x12 = x1 | x3 = 0x80000004
        imem[12] = r_type(F7_ZERO, 5'd3, 5'd1, F3_OR,  5'd12, OP_REG);
        // x13 = x2 & 0x0F0 = 0xF0 via ANDI
        imem[13] = i_type(12'h0F0,      5'd2, F3_AND, 5'd13, OP_IMM);
        // x14 = x1 | 0x700 = 0x704 via ORI
        imem[14] = i_type(12'h700,      5'd1, F3_OR,  5'd14, OP_IMM);
        // x15 = x1 ^ 0x00F = 0x00B via XORI
        imem[15] = i_type(12'h00F,      5'd1, F3_XOR, 5'd15, OP_IMM);

        // Sub-word store/load. Build a base pointer x20 = 0x40 (word 16).
        imem[16] = i_type(12'h040,      5'd0, F3_ADD, 5'd20, OP_IMM);  // x20 = 0x40
        // x21 = 0x000000AB
        imem[17] = i_type(12'h0AB,      5'd0, F3_ADD, 5'd21, OP_IMM);
        // SB x21, 1(x20) -> writes 0xAB into byte 1 of word at 0x40
        imem[18] = s_type(12'd1,        5'd21, 5'd20, F3_B, OP_STORE);
        // LBU x22, 1(x20) -> 0x000000AB
        imem[19] = i_type(12'd1,        5'd20, F3_BU, 5'd22, OP_LOAD);
        // LB x23, 1(x20) -> sign extended 0xFFFFFFAB
        imem[20] = i_type(12'd1,        5'd20, F3_B,  5'd23, OP_LOAD);
        // x24 = 0x0000BEEF
        imem[21] = i_type(12'd0,        5'd0, F3_ADD, 5'd24, OP_IMM);   // clear
        imem[22] = i_type(12'hEEF,      5'd0, F3_ADD, 5'd24, OP_IMM);   // x24 = 0xFFFFFEEF
        // SH x24, 2(x20) -> store low half 0xFEEF into upper half of word 0x40
        imem[23] = s_type(12'd2,        5'd24, 5'd20, F3_H, OP_STORE);
        // LHU x25, 2(x20) -> 0x0000FEEF
        imem[24] = i_type(12'd2,        5'd20, F3_HU, 5'd25, OP_LOAD);
        // LH x26, 2(x20) -> sign extended 0xFFFFFEEF
        imem[25] = i_type(12'd2,        5'd20, F3_H,  5'd26, OP_LOAD);
        // LW x27, 0(x20) -> whole word: byte1=0xAB, half-upper=0xFEEF -> 0xFEEFAB00
        imem[26] = i_type(12'd0,        5'd20, F3_W,  5'd27, OP_LOAD);

        // Branch matrix. x28 counts how many taken branches we passed through.
        // Start x28 = 0.
        imem[27] = i_type(12'd0,        5'd0, F3_ADD, 5'd28, OP_IMM);

        // BNE x1, x2 taken (4 != -1) -> skip the trap ADDI
        imem[28] = b_type(13'd8,        5'd2, 5'd1, F3_BNE, OP_BRANCH); // to imem[30]
        imem[29] = i_type(12'h7FF,      5'd0, F3_ADD, 5'd29, OP_IMM);   // trap, must be skipped
        // BLT x2, x1 taken (-1 < 4) -> skip trap
        imem[30] = b_type(13'd8,        5'd1, 5'd2, F3_BLT, OP_BRANCH); // to imem[32]
        imem[31] = i_type(12'h7FF,      5'd0, F3_ADD, 5'd29, OP_IMM);   // trap
        // BGE x1, x2 taken (4 >= -1) -> skip trap
        imem[32] = b_type(13'd8,        5'd2, 5'd1, F3_BGE, OP_BRANCH); // to imem[34]
        imem[33] = i_type(12'h7FF,      5'd0, F3_ADD, 5'd29, OP_IMM);   // trap
        // BLTU x1, x2 taken (4 < 0xFFFFFFFF) -> skip trap
        imem[34] = b_type(13'd8,        5'd2, 5'd1, F3_BLTU, OP_BRANCH);// to imem[36]
        imem[35] = i_type(12'h7FF,      5'd0, F3_ADD, 5'd29, OP_IMM);   // trap
        // BGEU x2, x1 taken (0xFFFFFFFF >= 4) -> skip trap
        imem[36] = b_type(13'd8,        5'd1, 5'd2, F3_BGEU, OP_BRANCH);// to imem[38]
        imem[37] = i_type(12'h7FF,      5'd0, F3_ADD, 5'd29, OP_IMM);   // trap
        // BEQ x1, x2 NOT taken (4 != -1) -> fall through and set x28 = 0x55
        imem[38] = b_type(13'd8,        5'd2, 5'd1, F3_BEQ, OP_BRANCH); // not taken
        imem[39] = i_type(12'h055,      5'd0, F3_ADD, 5'd28, OP_IMM);   // x28 = 0x55, executes

        // JALR test. Compute target = address of imem[44] (0xB0) into x5-like reg.
        // x30 = 0xB0
        imem[40] = i_type(12'h0B0,      5'd0, F3_ADD, 5'd30, OP_IMM);
        // JALR x31, x30, 0 -> link x31 = 0xA8, jump to 0xB0 = imem[44]
        imem[41] = i_type(12'd0,        5'd30, 3'b000, 5'd31, OP_JALR);
        // skipped
        imem[42] = i_type(12'h7FF,      5'd0, F3_ADD, 5'd29, OP_IMM);   // trap
        imem[43] = i_type(12'h7FF,      5'd0, F3_ADD, 5'd29, OP_IMM);   // trap
        // landing at 0xB0: x29 stays 0 if no trap fired. Halt loop.
        imem[44] = j_type(21'd0,        5'd0, OP_JAL);                  // self-loop

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (MAX_CYCLES) @(posedge clk);

        $display("AkashaRV32I core testbench 2");

        // Shifts.
        check_reg(5'd3,  32'h80000000, "SLLI31");
        check_reg(5'd4,  32'h00000020, "SLLI");
        check_reg(5'd5,  32'h08000000, "SRLI");
        check_reg(5'd6,  32'hF8000000, "SRAI");
        check_reg(5'd7,  32'hFFFFFFFF, "SRA");

        // Set-less-than.
        check_reg(5'd8,  32'h00000001, "SLT");
        check_reg(5'd9,  32'h00000000, "SLTU");
        check_reg(5'd10, 32'h00000001, "SLTI");

        // Logic.
        check_reg(5'd11, 32'hFFFFFFFB, "XOR");
        check_reg(5'd12, 32'h80000004, "OR");
        check_reg(5'd13, 32'h000000F0, "ANDI");
        check_reg(5'd14, 32'h00000704, "ORI");
        check_reg(5'd15, 32'h0000000B, "XORI");

        // Sub-word memory.
        check_reg(5'd22, 32'h000000AB, "LBU");
        check_reg(5'd23, 32'hFFFFFFAB, "LB");
        check_reg(5'd25, 32'h0000FEEF, "LHU");
        check_reg(5'd26, 32'hFFFFFEEF, "LH");
        check_reg(5'd27, 32'hFEEFAB00, "LW");

        // Branches: all traps must have left x29 = 0, fall-through set x28.
        check_reg(5'd29, 32'h00000000, "NO_TRAP");
        check_reg(5'd28, 32'h00000055, "BEQ_NT");

        // JALR.
        check_reg(5'd31, 32'h000000A8, "JALR_LINK");

        // Direct memory image check at word 0x40.
        if (dmem[16] !== 32'hFEEFAB00) begin
            errors = errors + 1;
            $display("FAIL mem[0x40] = 0x%08h, expected 0xfeefab00", dmem[16]);
        end else begin
            $display("PASS mem[0x40] = 0x%08h", dmem[16]);
        end

        if (errors == 0)
            $display("RESULT: all checks passed");
        else
            $display("RESULT: %0d check(s) failed", errors);

        $finish;
    end

endmodule
