//////////////////////////////////////////////////////////////////////////////////
// Module Name: fetch
// Description: Simple in-order fetch with icache handshake.
//   - launches one request at a time
//   - holds a pending request until icache_rvalid_i
//   - holds output valid until downstream ready_in consumes it
//   - flush squashes pending/output and redirects pc
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module fetch (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        flush_i,
  input  logic [31:0] flush_pc_i,

  input  logic        ready_in,
  output logic        valid_out,
  output logic [31:0] pc_out,
  output logic [31:0] instr_out,

  output logic        icache_en_o,
  output logic [31:0] icache_addr_o,
  input  logic [31:0] icache_rdata_i,
  input  logic        icache_rvalid_i
);

  logic [31:0] pc_q;

  logic        req_pending;
  logic [31:0] req_pc;

  logic        out_valid;
  logic [31:0] out_pc;
  logic [31:0] out_instr;

  assign valid_out = out_valid;
  assign pc_out    = out_pc;
  assign instr_out = out_instr;

  // icache request: pulse en when launching
  always @* begin
    icache_en_o   = 1'b0;
    icache_addr_o = pc_q;

    if (!out_valid && !req_pending) begin
      icache_en_o   = 1'b1;
      icache_addr_o = pc_q;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pc_q        <= 32'h0000_0000;
      req_pending <= 1'b0;
      req_pc      <= 32'h0;

      out_valid   <= 1'b0;
      out_pc      <= 32'h0;
      out_instr   <= 32'h0;
    end else begin
      if (flush_i) begin
        pc_q        <= flush_pc_i;
        req_pending <= 1'b0;
        out_valid   <= 1'b0;
      end else begin
        // consume output
        if (out_valid && ready_in) begin
          out_valid <= 1'b0;
        end

        // launch request if empty
        if (!out_valid && !req_pending) begin
          req_pending <= 1'b1;
          req_pc      <= pc_q;
        end

        // capture return
        if (req_pending && icache_rvalid_i) begin
          out_valid   <= 1'b1;
          out_pc      <= req_pc;
          out_instr   <= icache_rdata_i;

          req_pending <= 1'b0;
          pc_q        <= req_pc + 32'd4;
        end
      end
    end
  end

endmodule
