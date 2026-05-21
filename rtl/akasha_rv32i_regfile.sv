// SPDX-FileCopyrightText: AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: CERN-OHL-S-2.0

// 32 entry general purpose register file.
// Register x0 is hardwired to zero: reads always return zero and writes are
// discarded. Reads are combinational, writes are synchronous.

module akasha_rv32i_regfile #(
    parameter int DATA_WIDTH = 32
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  we,
    input  logic [4:0]            rd_addr,
    input  logic [DATA_WIDTH-1:0] rd_wdata,
    input  logic [4:0]            rs1_addr,
    input  logic [4:0]            rs2_addr,
    output logic [DATA_WIDTH-1:0] rs1_data,
    output logic [DATA_WIDTH-1:0] rs2_data
);

    logic [DATA_WIDTH-1:0] registers [1:31];

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 1; i < 32; i = i + 1) begin
                registers[i] <= '0;
            end
        end else if (we && (rd_addr != 5'd0)) begin
            registers[rd_addr] <= rd_wdata;
        end
    end

    // Write-through bypass: when WB and ID read the same register in the same
    // cycle, non-blocking assignment semantics mean the register array still
    // holds the old value during that clock edge. Return the incoming wdata
    // directly so the ID/EX latch captures the correct value.
    assign rs1_data = (rs1_addr == 5'd0)                       ? '0       :
                      (we && rd_addr == rs1_addr)               ? rd_wdata :
                                                                  registers[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0)                       ? '0       :
                      (we && rd_addr == rs2_addr)               ? rd_wdata :
                                                                  registers[rs2_addr];

endmodule
