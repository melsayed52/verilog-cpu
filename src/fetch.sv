////////////////////////////////////////////////////////////////////////////////
// Module: fetch
// Description: Single‑instruction fetch stage (Phase 1).
//
// This fetch unit retrieves one 32‑bit instruction per cycle from the
// instruction cache.  It increments the program counter by 4 on each
// accepted instruction and holds the output when downstream is not ready.
// Branch prediction is not yet implemented; a redirect input allows the
// decode/branch unit to jump to a new PC (e.g. for JALR).  Word‑aligned
// addressing is assumed (PC[1:0] == 2'b00).  The instruction cache has
// one cycle of latency.
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module fetch #(
  parameter logic [31:0] PC_RESET = 32'h0000_0000
)(
  input  logic        clk,
  input  logic        rst_n,

  // redirect (e.g., decoded JALR/branch)
  input  logic        pc_redir_valid,
  input  logic [31:0] pc_redir_target,

  // i‑cache interface (1‑cycle latency)
  output logic [31:2] icache_index,   // word index = PC[31:2]
  output logic        icache_en,      // read enable (one‑shot)
  input  logic [31:0] icache_rdata,   // returned instruction
  input  logic        icache_rvalid,  // valid in cycle after en

  // handshake to decode
  output logic [31:0] pc,
  output logic [31:0] instr,
  output logic        valid,
  input  logic        ready
);

  // State
  logic [31:0] pc_reg;
  logic [31:0] instr_reg;
  logic        valid_reg;
  logic        req_outstanding;  // we have issued a read and are waiting for rvalid

  // outputs
  assign pc    = pc_reg;
  assign instr = instr_reg;
  assign valid = valid_reg;

  // i‑cache command
  always_comb begin
    // Only issue when we don't hold a valid instr and not waiting on a return
    icache_en    = (!valid_reg) && (!req_outstanding);
    icache_index = pc_reg[31:2];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_reg          <= PC_RESET;
      instr_reg       <= 32'h0000_0013; // NOP
      valid_reg       <= 1'b0;
      req_outstanding <= 1'b0;
    end else begin
      // Highest priority: redirect takes effect immediately
      if (pc_redir_valid) begin
        pc_reg          <= pc_redir_target & 32'hFFFF_FFFE; // clear LSB (JALR semantics)
        valid_reg       <= 1'b0;   // drop any presented instruction
        req_outstanding <= 1'b0;   // cancel outstanding request
        // Next cycle, comb will issue a new read for new PC
      end else begin
        // Normal fetch pipeline
        if ((!valid_reg) && (!req_outstanding)) begin
          req_outstanding <= 1'b1;   // we just issued a read (icache_en=1 in comb)
        end
        if (icache_rvalid) begin
          instr_reg       <= icache_rdata;
          valid_reg       <= 1'b1;
          req_outstanding <= 1'b0;
        end
        if (valid_reg && ready) begin
          pc_reg    <= pc_reg + 32'd4;
          valid_reg <= 1'b0;
          // next cycle: issue read for new PC
        end
      end
    end
  end
endmodule