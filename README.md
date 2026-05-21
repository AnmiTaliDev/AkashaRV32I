# AkashaRV32I

### आकाश — ether, the fabric of space

A implementation of the RV32I base integer instruction set, written in SystemVerilog. 

## What this is

AkashaRV32I executes the complete RV32I user-level integer instruction set:
R-type, I-type, S-type, B-type, U-type and J-type instructions, plus the
`ECALL` and `EBREAK` system instructions which are treated as no-operations.
The design uses a simple valid/ready memory interface with independent
instruction and data ports, contains no vendor primitives, and avoids latches.

## Architecture overview

The core is a **single-cycle** design. Each instruction is fetched and fully
retired within one accepted clock cycle: the program counter advances only when
the instruction port handshake completes, and, for loads and stores, when the
data port handshake completes as well. A single-cycle organisation was chosen
because it is the simplest structure that still maps cleanly onto the required
module decomposition, it keeps the control logic free of hazard handling, and
it makes the datapath easy to follow end to end. Register and memory effects are
committed only when the instruction retires, so wait states on either memory
port stall the whole core without corrupting architectural state.

The datapath flows from program counter to instruction fetch, decode, register
read, immediate generation, ALU, optional memory access, and finally writeback,
with next-program-counter selection handling branches and jumps.

## Module hierarchy

| Module                 | File                          | Responsibility                                  |
|------------------------|-------------------------------|-------------------------------------------------|
| `akasha_rv32i_core`    | `rtl/akasha_rv32i_core.sv`    | Top level, program counter, datapath wiring     |
| `akasha_rv32i_decoder` | `rtl/akasha_rv32i_decoder.sv` | Field extraction and control signal generation  |
| `akasha_rv32i_imm_gen` | `rtl/akasha_rv32i_imm_gen.sv` | Immediate reconstruction and sign extension     |
| `akasha_rv32i_regfile` | `rtl/akasha_rv32i_regfile.sv` | 32 entry register file with hardwired `x0`      |
| `akasha_rv32i_alu`     | `rtl/akasha_rv32i_alu.sv`     | Arithmetic, logic, shift and comparison         |
| `akasha_rv32i_lsu`     | `rtl/akasha_rv32i_lsu.sv`     | Load and store alignment, byte enables          |

## Interface

| Signal       | Direction | Width | Description                          |
|--------------|-----------|-------|--------------------------------------|
| `clk`        | input     | 1     | System clock                         |
| `rst_n`      | input     | 1     | Asynchronous active-low reset        |
| `imem_addr`  | output    | 32    | Instruction fetch address            |
| `imem_req`   | output    | 1     | Instruction fetch request            |
| `imem_rdata` | input     | 32    | Instruction read data                |
| `imem_ready` | input     | 1     | Instruction memory ready             |
| `dmem_addr`  | output    | 32    | Data memory address                  |
| `dmem_wdata` | output    | 32    | Data memory write data               |
| `dmem_we`    | output    | 1     | Data memory write enable             |
| `dmem_be`    | output    | 4     | Data memory byte enable              |
| `dmem_req`   | output    | 1     | Data memory request                  |
| `dmem_rdata` | input     | 32    | Data memory read data                |
| `dmem_ready` | input     | 1     | Data memory ready                    |

Parameters `DATA_WIDTH` and `ADDR_WIDTH` both default to 32.

## How to simulate

### Icarus Verilog

```sh
iverilog -g2012 -o akasha_sim tb/akasha_rv32i_core_tb.sv rtl/*.sv
vvp akasha_sim
```

### Verilator

```sh
verilator --binary -j 0 --top-module akasha_rv32i_core_tb \
    tb/akasha_rv32i_core_tb.sv rtl/*.sv
./obj_dir/Vakasha_rv32i_core_tb
```

A successful run prints a per-register pass line for each checked value and
ends with `RESULT: all checks passed`.

## License

Licensed under CERN-OHL-S-2.0.

## Reference

The instruction set follows the RISC-V Instruction Set Manual, Volume I: Unprivileged ISA.
