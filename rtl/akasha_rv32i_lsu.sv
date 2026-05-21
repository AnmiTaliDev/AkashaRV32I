// SPDX-FileCopyrightText: AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: CERN-OHL-S-2.0

// Load/store unit for RV32I.
// Aligns store data and byte enables to the addressed sub-word and extracts
// and extends the addressed bytes for loads. The data memory is word
// addressed with byte granularity selected through dmem_be.

module akasha_rv32i_lsu #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32
) (
    input  logic                  mem_read,
    input  logic                  mem_write,
    input  logic [2:0]            funct3,
    input  logic [DATA_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] store_data,
    input  logic [DATA_WIDTH-1:0] dmem_rdata,

    output logic [ADDR_WIDTH-1:0] dmem_addr,
    output logic [DATA_WIDTH-1:0] dmem_wdata,
    output logic                  dmem_we,
    output logic [3:0]            dmem_be,
    output logic [DATA_WIDTH-1:0] load_data
);

    // Width encodings carried in funct3.
    localparam logic [2:0] WIDTH_B  = 3'b000;
    localparam logic [2:0] WIDTH_H  = 3'b001;
    localparam logic [2:0] WIDTH_W  = 3'b010;
    localparam logic [2:0] WIDTH_BU = 3'b100;
    localparam logic [2:0] WIDTH_HU = 3'b101;

    logic [1:0] byte_offset;
    assign byte_offset = addr[1:0];

    assign dmem_addr = {addr[ADDR_WIDTH-1:2], 2'b00};
    assign dmem_we   = mem_write;

    // Store path: replicate the source across the word and select the lanes.
    always_comb begin
        dmem_wdata = store_data;
        dmem_be    = 4'b0000;

        if (mem_write) begin
            unique case (funct3)
                WIDTH_B: begin
                    dmem_wdata = {4{store_data[7:0]}};
                    dmem_be    = 4'b0001 << byte_offset;
                end
                WIDTH_H: begin
                    dmem_wdata = {2{store_data[15:0]}};
                    dmem_be    = byte_offset[1] ? 4'b1100 : 4'b0011;
                end
                WIDTH_W: begin
                    dmem_wdata = store_data;
                    dmem_be    = 4'b1111;
                end
                default: begin
                    dmem_wdata = store_data;
                    dmem_be    = 4'b0000;
                end
            endcase
        end
    end

    // Load path: select the addressed bytes then sign or zero extend.
    logic [7:0]  byte_lane;
    logic [15:0] half_lane;

    always_comb begin
        unique case (byte_offset)
            2'b00:   byte_lane = dmem_rdata[7:0];
            2'b01:   byte_lane = dmem_rdata[15:8];
            2'b10:   byte_lane = dmem_rdata[23:16];
            2'b11:   byte_lane = dmem_rdata[31:24];
            default: byte_lane = dmem_rdata[7:0];
        endcase
    end

    always_comb begin
        half_lane = byte_offset[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];
    end

    always_comb begin
        unique case (funct3)
            WIDTH_B:  load_data = {{24{byte_lane[7]}}, byte_lane};
            WIDTH_H:  load_data = {{16{half_lane[15]}}, half_lane};
            WIDTH_W:  load_data = dmem_rdata;
            WIDTH_BU: load_data = {24'b0, byte_lane};
            WIDTH_HU: load_data = {16'b0, half_lane};
            default:  load_data = dmem_rdata;
        endcase
    end

endmodule
