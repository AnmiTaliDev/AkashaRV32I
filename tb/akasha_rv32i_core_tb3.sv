// SPDX-FileCopyrightText: AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: CERN-OHL-S-2.0

// Third testbench for the AkashaRV32I core.
// Exercises the dmem_stall path: the data memory model introduces a one-cycle
// wait state on every access (dmem_ready goes low for one cycle after each
// request). This validates that the pipeline correctly freezes all stages
// above MEM and does not lose the instruction sitting in ID during the stall.

`timescale 1ns / 1ps

module akasha_rv32i_core_tb3;

    localparam int DATA_WIDTH = 32;
    localparam int ADDR_WIDTH = 32;
    localparam int IMEM_WORDS = 256;
    localparam int DMEM_WORDS = 256;
    localparam int MAX_CYCLES = 400;

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

    localparam int IMEM_IDX_W = $clog2(IMEM_WORDS);
    localparam int DMEM_IDX_W = $clog2(DMEM_WORDS);

    logic [DATA_WIDTH-1:0] imem [0:IMEM_WORDS-1];
    logic [DATA_WIDTH-1:0] dmem [0:DMEM_WORDS-1];

    logic [IMEM_IDX_W-1:0] imem_index;
    logic [DMEM_IDX_W-1:0] dmem_index;
    assign imem_index = imem_addr[IMEM_IDX_W+1:2];
    assign dmem_index = dmem_addr[DMEM_IDX_W+1:2];

    // Instruction memory: zero wait state.
    assign imem_ready = 1'b1;
    assign imem_rdata = imem[imem_index];

    // Data memory: one-cycle wait state on every access.
    // dmem_ready goes low for one cycle after each new request arrives,
    // then returns high so the core can complete the transaction.
    logic dmem_ready_r;
    logic dmem_req_prev;

    assign dmem_ready = dmem_ready_r;
    assign dmem_rdata = dmem[dmem_index];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmem_ready_r  <= 1'b1;
            dmem_req_prev <= 1'b0;
        end else begin
            dmem_req_prev <= dmem_req;
            // When a new request arrives (req rising edge), drop ready for one cycle.
            if (dmem_req && !dmem_req_prev)
                dmem_ready_r <= 1'b0;
            else
                dmem_ready_r <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (dmem_req && dmem_we && dmem_ready) begin
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

    localparam logic [6:0] OP_JAL    = 7'b1101111;
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_LOAD   = 7'b0000011;
    localparam logic [6:0] OP_STORE  = 7'b0100011;
    localparam logic [6:0] OP_IMM    = 7'b0010011;
    localparam logic [6:0] OP_REG    = 7'b0110011;

    localparam logic [2:0] F3_ADD  = 3'b000;
    localparam logic [2:0] F3_BEQ  = 3'b000;
    localparam logic [2:0] F3_W    = 3'b010;
    localparam logic [6:0] F7_ZERO = 7'b0000000;
    localparam logic [6:0] F7_SUB  = 7'b0100000;

    integer errors;

    task automatic check_reg(input [4:0] idx, input logic [31:0] exp, input string label);
        logic [31:0] actual;
        actual = dut.u_regfile.registers[idx];
        if (actual !== exp) begin
            errors = errors + 1;
            $display("FAIL %-12s x%0d = 0x%08h, expected 0x%08h", label, idx, actual, exp);
        end else begin
            $display("PASS %-12s x%0d = 0x%08h", label, idx, actual);
        end
    endtask

    integer k;

    initial begin
        errors = 0;

        for (k = 0; k < IMEM_WORDS; k++) imem[k] = 32'h00000013;
        for (k = 0; k < DMEM_WORDS; k++) dmem[k] = 32'h00000000;

        // Program tests three scenarios that exercise dmem stall:
        //
        // 1. SW followed immediately by arithmetic — the instruction in ID
        //    during the store stall must survive and produce a correct result.
        //
        // 2. LW followed immediately by an instruction that uses the loaded
        //    value — load-use stall plus dmem stall stack.
        //
        // 3. Multiple back-to-back loads to confirm the pipeline drains
        //    correctly under repeated dmem stalls.

        // x1 = 7, x2 = 3
        imem[0]  = i_type(12'd7,  5'd0, F3_ADD, 5'd1, OP_IMM);
        imem[1]  = i_type(12'd3,  5'd0, F3_ADD, 5'd2, OP_IMM);
        // SW x1, 0(x0) — triggers one dmem stall cycle
        imem[2]  = s_type(12'd0, 5'd1, 5'd0, F3_W, OP_STORE);
        // This instruction sits in ID during the stall; must not be lost.
        // x3 = x1 + x2 = 10
        imem[3]  = r_type(F7_ZERO, 5'd2, 5'd1, F3_ADD, 5'd3, OP_REG);
        // x4 = x3 + x2 = 13
        imem[4]  = r_type(F7_ZERO, 5'd2, 5'd3, F3_ADD, 5'd4, OP_REG);

        // LW x5, 0(x0) — load from address 0 (we stored 7 there).
        // Triggers dmem stall AND load-use stall (x6 uses x5 immediately).
        imem[5]  = i_type(12'd0, 5'd0, F3_W, 5'd5, OP_LOAD);
        // x6 = x5 + x2 = 7 + 3 = 10 (load-use stall inserts one bubble)
        imem[6]  = r_type(F7_ZERO, 5'd2, 5'd5, F3_ADD, 5'd6, OP_REG);

        // SW x2, 4(x0), then SW x1, 8(x0) — two back-to-back stores
        imem[7]  = s_type(12'd4,  5'd2, 5'd0, F3_W, OP_STORE);
        imem[8]  = s_type(12'd8,  5'd1, 5'd0, F3_W, OP_STORE);
        // Two back-to-back loads, each stalls for one cycle.
        imem[9]  = i_type(12'd4,  5'd0, F3_W, 5'd7, OP_LOAD);
        imem[10] = i_type(12'd8,  5'd0, F3_W, 5'd8, OP_LOAD);
        // x9 = x7 + x8 = 3 + 7 = 10
        imem[11] = r_type(F7_ZERO, 5'd8, 5'd7, F3_ADD, 5'd9, OP_REG);

        // Branch test under stall: BEQ x1, x1, +8 (taken, skips imem[13])
        imem[12] = b_type(13'd8, 5'd1, 5'd1, F3_BEQ, OP_BRANCH);
        imem[13] = i_type(12'h7FF, 5'd0, F3_ADD, 5'd10, OP_IMM); // trap
        // x11 = 42
        imem[14] = i_type(12'd42, 5'd0, F3_ADD, 5'd11, OP_IMM);

        // Halt.
        imem[15] = j_type(21'd0, 5'd0, OP_JAL);

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (MAX_CYCLES) @(posedge clk);

        $display("AkashaRV32I core testbench 3 (dmem stall)");
        check_reg(5'd3,  32'd10,  "ADD_after_SW");
        check_reg(5'd4,  32'd13,  "ADD_after_ADD");
        check_reg(5'd5,  32'd7,   "LW");
        check_reg(5'd6,  32'd10,  "ADD_load_use");
        check_reg(5'd7,  32'd3,   "LW_x7");
        check_reg(5'd8,  32'd7,   "LW_x8");
        check_reg(5'd9,  32'd10,  "ADD_back2back");
        check_reg(5'd10, 32'd0,   "BRANCH_skip");
        check_reg(5'd11, 32'd42,  "BRANCH_land");

        if (dmem[0] !== 32'd7) begin
            errors++;
            $display("FAIL dmem[0] = 0x%08h, expected 0x00000007", dmem[0]);
        end else
            $display("PASS dmem[0] = 0x%08h", dmem[0]);

        if (errors == 0)
            $display("RESULT: all checks passed");
        else
            $display("RESULT: %0d check(s) failed", errors);

        $finish;
    end

endmodule
