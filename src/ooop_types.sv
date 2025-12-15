`ifndef OOOP_TYPES_SV
`define OOOP_TYPES_SV

`include "ooop_defs.vh"

package ooop_types;

  // ---------------------------------------------------------------------------
  // Parameters mirrored from ooop_defs.vh so modules can use ooop_types::XXX
  // ---------------------------------------------------------------------------
  localparam int XLEN        = `XLEN;
  localparam int N_ARCH_REGS = `N_ARCH_REGS;
  localparam int N_PHYS_REGS = `N_PHYS_REGS;

  localparam int ROB_DEPTH   = `ROB_DEPTH;
  localparam int RS_DEPTH    = `RS_DEPTH;

  localparam int REG_W       = `REG_W;
  localparam int PREG_W      = `PREG_W;
  localparam int ROB_W       = `ROB_W;
  localparam int RS_W        = `RS_W;

  typedef logic [XLEN-1:0] xlen_t;

  // ---------------------------------------------------------------------------
  // Enums
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    FU_ALU  = 2'd0,
    FU_BRU  = 2'd1,
    FU_LSU  = 2'd2,
    FU_NONE = 2'd3
  } fu_type_t;

  // NOTE: must cover ops used by decode + alu_fu
  typedef enum logic [3:0] {
    ALU_ADD   = 4'd0,
    ALU_SUB   = 4'd1,
    ALU_AND   = 4'd2,
    ALU_OR    = 4'd3,
    ALU_XOR   = 4'd4,
    ALU_SLT   = 4'd5,
    ALU_SLTU  = 4'd6,
    ALU_SLL   = 4'd7,
    ALU_SRL   = 4'd8,
    ALU_SRA   = 4'd9,
    ALU_SLTIU = 4'd10,
    ALU_LUI   = 4'd11
  } alu_op_t;

  typedef enum logic [1:0] {
    LS_B = 2'd0,
    LS_H = 2'd1,
    LS_W = 2'd2
  } ls_size_t;

  // ---------------------------------------------------------------------------
  // Packets / entries
  // ---------------------------------------------------------------------------

  typedef struct packed {
    logic         valid;
    xlen_t        pc;
    logic [31:0]  instr;
  } fetch_pkt_t;

  typedef struct packed {
    logic         valid;
    xlen_t        pc;
    logic [31:0]  instr;

    logic [REG_W-1:0] rs1;
    logic [REG_W-1:0] rs2;
    logic [REG_W-1:0] rd;

    // FIX: decode.sv already drives these, so types must include them
    logic         rs1_used;
    logic         rs2_used;

    xlen_t        imm;
    logic         imm_used;

    fu_type_t     fu_type;
    alu_op_t      alu_op;

    logic         rd_used;

    logic         is_load;
    logic         is_store;
    ls_size_t     ls_size;
    logic         unsigned_load;

    logic         is_branch;
    logic         is_jump;
    logic         is_jalr;
  } decode_pkt_t;

  typedef struct packed {
    logic         valid;
    xlen_t        pc;
    logic [31:0]  instr;

    logic [REG_W-1:0] rs1;
    logic [REG_W-1:0] rs2;
    logic [REG_W-1:0] rd;

    xlen_t        imm;
    logic         imm_used;

    fu_type_t     fu_type;
    alu_op_t      alu_op;

    logic         rd_used;

    logic         is_load;
    logic         is_store;
    ls_size_t     ls_size;
    logic         unsigned_load;

    logic         is_branch;
    logic         is_jump;
    logic         is_jalr;
    
    logic         rs1_used;
    logic         rs2_used;

    logic [PREG_W-1:0] prs1;
    logic [PREG_W-1:0] prs2;
    logic [PREG_W-1:0] prd;

    logic         prs1_ready;
    logic         prs2_ready;

    logic [PREG_W-1:0] old_prd;
    logic [ROB_W-1:0]  rob_tag;
  } rename_pkt_t;

  typedef struct packed {
    logic         valid;

    xlen_t        pc;
    logic [31:0]  instr;

    fu_type_t     fu_type;
    alu_op_t      alu_op;

    xlen_t        imm;
    logic         imm_used;

    logic         rd_used;

    logic         is_load;
    logic         is_store;
    ls_size_t     ls_size;
    logic         unsigned_load;

    logic         is_branch;
    logic         is_jump;
    logic         is_jalr;
    
    logic         rs1_used;
    logic         rs2_used;

    logic [PREG_W-1:0] prs1;
    logic [PREG_W-1:0] prs2;
    logic [PREG_W-1:0] prd;

    logic         prs1_ready;
    logic         prs2_ready;

    logic [ROB_W-1:0]  rob_tag;
  } rs_entry_t;

  // FU completion "WB bus" packet (3 buses: ALU/LSU/BRU)
  typedef struct packed {
    logic              valid;
    logic [ROB_W-1:0]  rob_tag;
    logic [PREG_W-1:0] prd;
    xlen_t             data;
    logic              rd_used;
  } wb_pkt_t;

endpackage

`endif // OOOP_TYPES_SV
