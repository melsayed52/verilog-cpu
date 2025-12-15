//////////////////////////////////////////////////////////////////////////////////
// Module Name: lsu_fu
// Description: LSU FU (phase 3/4) using BRAM-style DMEM ports (2-cycle latency).
// Additional Comments:
//   - FIX: flush hazard protection for 2-cycle memory:
//       after flush_i, block new issues for 2 cycles and ignore responses
//       during the block, preventing old responses from pairing with new metadata.
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "ooop_defs.vh"
`include "ooop_types.sv"

module lsu_fu (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  flush_i,

  input  logic                  issue_valid_i,
  input  ooop_types::rs_entry_t  entry_i,
  input  ooop_types::xlen_t      src1_i,
  input  ooop_types::xlen_t      src2_i,

  output logic                  dmem_en_o,
  output logic                  dmem_we_o,
  output logic [31:0]           dmem_addr_o,
  output logic [31:0]           dmem_wdata_o,
  output ooop_types::ls_size_t  dmem_size_o,

  input  logic                  dmem_rvalid_i,
  input  logic [31:0]           dmem_rdata_i,

  output ooop_types::wb_pkt_t   wb_o
);

  import ooop_types::*;

  // 2-cycle post-flush block window
  logic [1:0] block_cnt;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      block_cnt <= 2'd0;
    end else begin
      if (flush_i) begin
        block_cnt <= 2'd2;
      end else if (block_cnt != 2'd0) begin
        block_cnt <= block_cnt - 2'd1;
      end
    end
  end

  wire allow_issue = (block_cnt == 2'd0) && !flush_i;

  logic [31:0] eff_addr;
  assign eff_addr = src1_i + entry_i.imm;

  // suppress requests during block
  assign dmem_en_o    = issue_valid_i && allow_issue;
  assign dmem_we_o    = entry_i.is_store;
  assign dmem_addr_o  = eff_addr;
  assign dmem_wdata_o = src2_i;
  assign dmem_size_o  = entry_i.ls_size;

  typedef struct packed {
    logic              v;
    logic              is_load;
    logic              rd_used;
    logic [ROB_W-1:0]  rob_tag;
    logic [PREG_W-1:0] prd;
    ls_size_t          size;
    logic              uns;
    logic [1:0]        off;
  } meta_t;

  meta_t m0_q, m1_q;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      m0_q <= '0;
      m1_q <= '0;
    end else if (flush_i) begin
      m0_q <= '0;
      m1_q <= '0;
    end else begin
      // stage0 capture only when allowed
      m0_q.v <= issue_valid_i && allow_issue;
      if (issue_valid_i && allow_issue) begin
        m0_q.is_load <= entry_i.is_load;
        m0_q.rd_used <= entry_i.rd_used;
        m0_q.rob_tag <= entry_i.rob_tag;
        m0_q.prd     <= entry_i.prd;
        m0_q.size    <= entry_i.ls_size;
        m0_q.uns     <= entry_i.unsigned_load;
        m0_q.off     <= eff_addr[1:0];
      end else begin
        m0_q.is_load <= 1'b0;
        m0_q.rd_used <= 1'b0;
        m0_q.rob_tag <= '0;
        m0_q.prd     <= '0;
        m0_q.size    <= LS_W;
        m0_q.uns     <= 1'b0;
        m0_q.off     <= 2'd0;
      end

      // stage1 shift
      m1_q <= m0_q;
    end
  end

  logic [31:0] load_res;

  always @* begin
    load_res = dmem_rdata_i;

    unique case (m1_q.size)
      LS_B: begin
        logic [7:0] b;
        unique case (m1_q.off)
          2'd0: b = dmem_rdata_i[7:0];
          2'd1: b = dmem_rdata_i[15:8];
          2'd2: b = dmem_rdata_i[23:16];
          default: b = dmem_rdata_i[31:24];
        endcase
        load_res = m1_q.uns ? {24'd0, b} : {{24{b[7]}}, b};
      end

      LS_H: begin
        logic [15:0] h;
        h = m1_q.off[1] ? dmem_rdata_i[31:16] : dmem_rdata_i[15:0];
        load_res = m1_q.uns ? {16'd0, h} : {{16{h[15]}}, h};
      end

      default: begin
        load_res = dmem_rdata_i;
      end
    endcase
  end

  always @* begin
    wb_o = '0;

    if (dmem_rvalid_i && m1_q.v && (block_cnt == 2'd0) && !flush_i) begin
      wb_o.valid   = 1'b1;
      wb_o.rob_tag = m1_q.rob_tag;

      if (m1_q.is_load && m1_q.rd_used) begin
        wb_o.rd_used = 1'b1;
        wb_o.prd     = m1_q.prd;
        wb_o.data    = load_res;
      end else begin
        wb_o.rd_used = 1'b0;
        wb_o.prd     = '0;
        wb_o.data    = 32'd0;
      end
    end
  end

endmodule
