////////////////////////////////////////////////////////////////////////////////
// Module: rename
// Description: Simple register renaming stage.
//
// This rename implementation performs architectural to physical register
// renaming with a single entry of buffering.  When a new instruction
// arrives, the RAT table is consulted to find the physical tags for rs1 and
// rs2.  A new physical tag for the destination is allocated from an
// internal counter; the old tag for rd is captured.  Readiness of each
// source operand is determined by looking up the validity bit in the
// physical register file (provided as the prf_valid vector).  The module
// updates the RAT immediately when rd is used.  When the downstream
// dispatch is unable to accept an instruction (ready_in = 0) the current
// rename result is held in a register until it is consumed.
//
// NOTE: This simplified rename does not implement a freelist – it
// allocates physical tags sequentially from N_ARCH_REGS upwards and does
// not reclaim them.  For short traces this suffices; a real design would
// integrate a freelist and use commit signals to recycle tags.
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "ooop_defs.vh"

module rename #(
  parameter XLEN_P      = XLEN,
  parameter PREG_W_P    = PREG_W,
  parameter ROB_TAG_W_P = ROB_TAG_W
)(
  input                       clk,
  input                       rst_n,

  input                       valid_in,
  output                      ready_out,

  input      [31:0]           pc_in,
  input      [4:0]            rs1_arch,
  input      [4:0]            rs2_arch,
  input      [4:0]            rd_arch,

  input      [XLEN_P-1:0]     imm_in,
  input                       imm_used_in,
  input      [1:0]            fu_type_in,
  input      [3:0]            alu_op_in,
  input                       rd_used_in,
  input                       is_load_in,
  input                       is_store_in,
  input      [1:0]            ls_size_in,
  input                       unsigned_load_in,
  input                       is_branch_in,
  input                       is_jump_in,

  // Physical register validity (from PRF) for readiness
  input      [N_PHYS_REGS-1:0] prf_valid,

  output                      valid_out,
  input                       ready_in,

  output reg [31:0]           pc_out,
  output reg [1:0]            fu_type_out,
  output reg [3:0]            alu_op_out,
  output reg [XLEN_P-1:0]     imm_out,
  output reg                  imm_used_out,
  output reg                  is_load_out,
  output reg                  is_store_out,
  output reg [1:0]            ls_size_out,
  output reg                  unsigned_load_out,
  output reg                  is_branch_out,
  output reg                  is_jump_out,

  output reg [ROB_TAG_W_P-1:0] rob_tag_out,

  output reg [PREG_W_P-1:0]   rs1_tag_out,
  output reg                  rs1_ready_out,
  output reg [PREG_W_P-1:0]   rs2_tag_out,
  output reg                  rs2_ready_out,

  output reg                  rd_used_out,
  output reg [PREG_W_P-1:0]   rd_new_tag_out,
  output reg [PREG_W_P-1:0]   rd_old_tag_out
);

  // Register alias table: maps architectural regs to physical tags
  reg [PREG_W_P-1:0] rat_table [0:N_ARCH_REGS-1];
  // Next physical tag to allocate; simple counter starting at N_ARCH_REGS
  reg [PREG_W_P-1:0] next_tag;

  // Output valid flag and buffered fields
  reg                out_valid;
  reg [31:0]         pc_buf;
  reg [1:0]          fu_type_buf;
  reg [3:0]          alu_op_buf;
  reg [XLEN_P-1:0]   imm_buf;
  reg                imm_used_buf;
  reg                is_load_buf;
  reg                is_store_buf;
  reg [1:0]          ls_size_buf;
  reg                unsigned_load_buf;
  reg                is_branch_buf;
  reg                is_jump_buf;
  reg [ROB_TAG_W_P-1:0] rob_tag_buf;
  reg [PREG_W_P-1:0] rs1_tag_buf;
  reg                rs1_ready_buf;
  reg [PREG_W_P-1:0] rs2_tag_buf;
  reg                rs2_ready_buf;
  reg                rd_used_buf;
  reg [PREG_W_P-1:0] rd_new_tag_buf;
  reg [PREG_W_P-1:0] rd_old_tag_buf;

  assign valid_out = out_valid;

  // Compute when we can accept a new instruction.  We can accept when
  // (1) there is no buffered output, or (2) the current output is being
  // consumed by downstream this cycle (ready_in=1).  We ignore tag pool
  // exhaustion for this simplified design.
  assign ready_out = (!out_valid) || (out_valid && ready_in);

  integer i;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      // Initialize RAT to identity mapping
      for (i = 0; i < N_ARCH_REGS; i = i + 1) begin
        rat_table[i] <= i[PREG_W_P-1:0];
      end
      next_tag   <= N_ARCH_REGS[PREG_W_P-1:0];
      out_valid  <= 1'b0;
    end else begin
      // If the current output is valid and downstream is ready, drop it
      if (out_valid && ready_in) begin
        out_valid <= 1'b0;
      end
      // Accept a new instruction when ready_out and valid_in
      if (valid_in && ready_out) begin
        // Read source tags from RAT
        reg [PREG_W_P-1:0] rs1_tag;
        reg [PREG_W_P-1:0] rs2_tag;
        reg [PREG_W_P-1:0] rd_old_tag;
        rs1_tag   = rat_table[rs1_arch];
        rs2_tag   = rat_table[rs2_arch];
        rd_old_tag= rat_table[rd_arch];
        // Determine readiness via prf_valid
        reg rs1_ready;
        reg rs2_ready;
        if (rs1_arch == 5'd0) rs1_ready = 1'b1; else rs1_ready = prf_valid[rs1_tag];
        if (rs2_arch == 5'd0) rs2_ready = 1'b1; else rs2_ready = prf_valid[rs2_tag];
        // Allocate new dest tag if rd is used and not x0
        reg [PREG_W_P-1:0] new_tag;
        reg                dest_used;
        if (rd_used_in && (rd_arch != 5'd0)) begin
          new_tag   = next_tag;
          dest_used = 1'b1;
        end else begin
          new_tag   = '0;
          dest_used = 1'b0;
        end
        // Update RAT immediately for rd
        if (dest_used) begin
          rat_table[rd_arch] <= new_tag;
          next_tag          <= next_tag + 1'b1;
        end
        // Buffer output fields
        pc_buf            <= pc_in;
        fu_type_buf       <= fu_type_in;
        alu_op_buf        <= alu_op_in;
        imm_buf           <= imm_in;
        imm_used_buf      <= imm_used_in;
        is_load_buf       <= is_load_in;
        is_store_buf      <= is_store_in;
        ls_size_buf       <= ls_size_in;
        unsigned_load_buf <= unsigned_load_in;
        is_branch_buf     <= is_branch_in;
        is_jump_buf       <= is_jump_in;
        rob_tag_buf       <= '0; // placeholder; actual tag allocated in dispatch
        rs1_tag_buf       <= rs1_tag;
        rs2_tag_buf       <= rs2_tag;
        rs1_ready_buf     <= rs1_ready;
        rs2_ready_buf     <= rs2_ready;
        rd_used_buf       <= dest_used;
        rd_new_tag_buf    <= new_tag;
        rd_old_tag_buf    <= rd_old_tag;
        // Mark output as valid
        out_valid         <= 1'b1;
      end
    end
  end

  // Drive outputs from buffered registers
  always_comb begin
    pc_out            = pc_buf;
    fu_type_out       = fu_type_buf;
    alu_op_out        = alu_op_buf;
    imm_out           = imm_buf;
    imm_used_out      = imm_used_buf;
    is_load_out       = is_load_buf;
    is_store_out      = is_store_buf;
    ls_size_out       = ls_size_buf;
    unsigned_load_out = unsigned_load_buf;
    is_branch_out     = is_branch_buf;
    is_jump_out       = is_jump_buf;
    rob_tag_out       = rob_tag_buf;
    rs1_tag_out       = rs1_tag_buf;
    rs2_tag_out       = rs2_tag_buf;
    rs1_ready_out     = rs1_ready_buf;
    rs2_ready_out     = rs2_ready_buf;
    rd_used_out       = rd_used_buf;
    rd_new_tag_out    = rd_new_tag_buf;
    rd_old_tag_out    = rd_old_tag_buf;
  end

endmodule