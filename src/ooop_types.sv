////////////////////////////////////////////////////////////////////////////////
// File: ooop_types.sv
// Description: Packed structs used for renaming and dispatch.
//
// To avoid long port lists on reservation stations and dispatch modules, the
// out‑of‑order design collects related fields into packed structs.  The
// rename packet contains all information produced by the rename stage,
// including operand tags and readiness flags, while the issue packet is a
// distilled version used when issuing to execution units.  These types are
// defined in SystemVerilog so that individual fields can be accessed by
// name without resorting to vectors and indices.
////////////////////////////////////////////////////////////////////////////////

`ifndef OOOP_TYPES_SV
`define OOOP_TYPES_SV

`include "ooop_defs.vh"

// Packet travelling from rename to dispatch.  This struct captures the
// architectural instruction as well as rename information such as source and
// destination tags.  The `rd_used` flag indicates whether an instruction
// writes to a destination register; when it is zero the rd_new_tag and
// rd_old_tag fields are don't‑care.  The rob_tag field is provided by
// rename as a placeholder – the actual ROB tag is allocated in dispatch.
typedef struct packed {
  logic [31:0]           pc;
  logic [1:0]            fu_type;
  logic [3:0]            alu_op;
  logic [XLEN-1:0]       imm;
  logic                  imm_used;
  logic                  is_load;
  logic                  is_store;
  logic [1:0]            ls_size;
  logic                  unsigned_load;
  logic                  is_branch;
  logic                  is_jump;
  logic [ROB_TAG_W-1:0]  rob_tag;
  logic [PREG_W-1:0]     rs1_tag;
  logic                  rs1_ready;
  logic [PREG_W-1:0]     rs2_tag;
  logic                  rs2_ready;
  logic                  rd_used;
  logic [PREG_W-1:0]     rd_new_tag;
  logic [PREG_W-1:0]     rd_old_tag;
} rename_pkt_t;

// Packet travelling from a reservation station to an execution unit and
// eventually onto the common data bus.  Many fields are copied directly
// from the rename packet, but the ready bits are not needed – by the time
// an instruction issues both operands are guaranteed ready.  The rd_tag
// field is the same as the rd_new_tag in rename_pkt_t but is renamed here
// for clarity.
typedef struct packed {
  logic [31:0]           pc;
  logic [1:0]            fu_type;
  logic [3:0]            alu_op;
  logic [XLEN-1:0]       imm;
  logic                  imm_used;
  logic                  is_load;
  logic                  is_store;
  logic [1:0]            ls_size;
  logic                  unsigned_load;
  logic                  is_branch;
  logic                  is_jump;
  logic [ROB_TAG_W-1:0]  rob_tag;
  logic [PREG_W-1:0]     rs1_tag;
  logic [PREG_W-1:0]     rs2_tag;
  logic                  rd_used;
  logic [PREG_W-1:0]     rd_tag;
} issue_pkt_t;

`endif // OOOP_TYPES_SV