//////////////////////////////////////////////////////////////////////////////////
// Module Name: lsu_fu
// Description: Load/store unit functional block (Phase 3: loads only).
//              Accepts issued memory operations from the LSU reservation
//              station, computes the effective address using rs1 (+ rs2 or
//              immediate), performs a load through dmem, and produces
//              writeback and ROB completion signals.
// Additional Comments:
//   - Uses issue_pkt_t fields: rs1_tag, rs2_tag, rd_tag, rd_used, imm,
//     imm_used, is_load, is_store, ls_size, unsigned_load, rob_tag.
//   - Stores are ignored in Phase 3 (can be added later).
//
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

`include "ooop_defs.vh"
`include "ooop_types.sv"

module lsu_fu #(
  parameter int XLEN_P = XLEN
)(
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 flush_i,

  // From LSU reservation station
  input  logic                 issue_valid_i,
  output logic                 issue_ready_o,
  input  issue_pkt_t           issue_pkt_i,

  // PRF combinational read ports (typically only rs1 is needed)
  output logic [PREG_W-1:0]    prf_rs1_tag_o,
  output logic [PREG_W-1:0]    prf_rs2_tag_o,
  input  logic [XLEN_P-1:0]    prf_rs1_data_i,
  input  logic [XLEN_P-1:0]    prf_rs2_data_i,

  // Interface to data memory
  output logic                 dmem_req_valid_o,
  output logic [31:0]          dmem_addr_o,
  input  logic [XLEN_P-1:0]    dmem_rdata_i,
  input  logic                 dmem_rvalid_i,

  // Writeback to CDB / PRF
  output logic                 wb_valid_o,
  output logic [PREG_W-1:0]    wb_tag_o,
  output logic [XLEN_P-1:0]    wb_data_o,

  // Completion to ROB
  output logic                 cpl_valid_o,
  output logic [ROB_TAG_W-1:0] cpl_tag_o
);

  // ---------------------------------------------------------------------------
  // PRF read tags
  // ---------------------------------------------------------------------------
  assign prf_rs1_tag_o = issue_pkt_i.rs1_tag;
  assign prf_rs2_tag_o = issue_pkt_i.rs2_tag;

  // ---------------------------------------------------------------------------
  // Simple 2-state FSM: IDLE -> WAIT_MEM
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {LSU_IDLE, LSU_WAIT_MEM} lsu_state_e;

  lsu_state_e        state_q, state_d;
  issue_pkt_t        pkt_q;
  logic [XLEN_P-1:0] addr_q;
  logic [XLEN_P-1:0] load_data_q;

  // Can accept a new issue only when idle
  assign issue_ready_o = (state_q == LSU_IDLE);

  // Effective address (combinational) for the current issue
  logic [XLEN_P-1:0] eff_addr_d;

  always_comb begin
    // base = rs1; offset can be imm or rs2
    logic [XLEN_P-1:0] offset;
    offset     = issue_pkt_i.imm_used ? issue_pkt_i.imm : prf_rs2_data_i;
    eff_addr_d = prf_rs1_data_i + offset;
  end

  // Memory request generation: fire when we accept an LSU issue
  assign dmem_req_valid_o = issue_valid_i && issue_ready_o && issue_pkt_i.is_load;
  assign dmem_addr_o      = eff_addr_d[31:0];

  // FSM next-state logic
  always_comb begin
    state_d = state_q;

    unique case (state_q)
      LSU_IDLE: begin
        if (issue_valid_i && issue_ready_o && issue_pkt_i.is_load) begin
          state_d = LSU_WAIT_MEM;
        end
      end

      LSU_WAIT_MEM: begin
        if (dmem_rvalid_i) begin
          state_d = LSU_IDLE;
        end
      end

      default: state_d = LSU_IDLE;
    endcase
  end

  // Sequential state + packet/addr capturing
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q      <= LSU_IDLE;
      pkt_q        <= '0;
      addr_q       <= '0;
      load_data_q  <= '0;
    end else if (flush_i) begin
      state_q      <= LSU_IDLE;
      pkt_q        <= '0;
    end else begin
      state_q <= state_d;

      if (issue_valid_i && issue_ready_o && issue_pkt_i.is_load) begin
        pkt_q  <= issue_pkt_i;
        addr_q <= eff_addr_d;
      end

      if ((state_q == LSU_WAIT_MEM) && dmem_rvalid_i) begin
        // Data formatting is handled below; store formatted value
        // into load_data_q.
        load_data_q <= format_load(dmem_rdata_i, addr_q[1:0],
                                   pkt_q.ls_size, pkt_q.unsigned_load);
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Load-format helper function: byte/halfword/word + sign/zero extend
  // ---------------------------------------------------------------------------
  function automatic logic [XLEN_P-1:0] format_load(
    input logic [XLEN_P-1:0] raw,
    input logic [1:0]        addr_low,
    input logic [1:0]        ls_size,
    input logic              unsigned_load
  );
    logic [XLEN_P-1:0] result;
    logic [7:0]  byte_lane;
    logic [15:0] half_lane;

    begin
      // Select byte/halfword based on low address bits
      case (ls_size)
        2'b00: begin
          // Byte
          case (addr_low)
            2'b00: byte_lane = raw[7:0];
            2'b01: byte_lane = raw[15:8];
            2'b10: byte_lane = raw[23:16];
            default: byte_lane = raw[31:24];
          endcase
          result = unsigned_load
            ? {{(XLEN_P-8){1'b0}}, byte_lane}
            : {{(XLEN_P-8){byte_lane[7]}}, byte_lane};
        end

        2'b01: begin
          // Halfword
          case (addr_low[1])
            1'b0: half_lane = raw[15:0];
            1'b1: half_lane = raw[31:16];
          endcase
          result = unsigned_load
            ? {{(XLEN_P-16){1'b0}}, half_lane}
            : {{(XLEN_P-16){half_lane[15]}}, half_lane};
        end

        default: begin
          // Word (assume aligned)
          result = raw;
        end
      endcase

      format_load = result;
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Writeback + completion
  // ---------------------------------------------------------------------------
  logic load_fire;
  assign load_fire = (state_q == LSU_WAIT_MEM) && dmem_rvalid_i;

  assign wb_valid_o  = load_fire && pkt_q.rd_used;
  assign wb_tag_o    = pkt_q.rd_tag;
  assign wb_data_o   = load_data_q;

  assign cpl_valid_o = load_fire;
  assign cpl_tag_o   = pkt_q.rob_tag;

endmodule
