//////////////////////////////////////////////////////////////////////////////////
// Module Name: fetch
// Description: In-order fetch with icache handshake and BTB-based branch prediction.
//   - launches one request at a time
//   - holds a pending request until icache_rvalid_i
//   - holds output valid until downstream ready_in consumes it
//   - flush squashes pending/output and redirects pc
//   - BTB lookup on fetch, speculative redirect on predicted-taken
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
  output logic        predicted_taken_out,
  output logic [31:0] predicted_target_out,

  output logic        icache_en_o,
  output logic [31:0] icache_addr_o,
  input  logic [31:0] icache_rdata_i,
  input  logic        icache_rvalid_i,

  // BTB lookup interface
  output logic [31:0] btb_lookup_pc_o,
  input  logic        btb_lookup_hit_i,
  input  logic        btb_lookup_taken_i,
  input  logic [31:0] btb_lookup_target_i
);

  logic [31:0] pc_q;

  logic        req_pending;
  logic [31:0] req_pc;

  logic        out_valid;
  logic [31:0] out_pc;
  logic [31:0] out_instr;
  logic        out_pred_taken;
  logic [31:0] out_pred_target;

  assign valid_out           = out_valid;
  assign pc_out              = out_pc;
  assign instr_out           = out_instr;
  assign predicted_taken_out = out_pred_taken;
  assign predicted_target_out= out_pred_target;

  // BTB lookup is combinational on pc_q
  assign btb_lookup_pc_o = pc_q;

  // Decode opcode from fetched instruction to check if it's a branch/jump
  wire [6:0] fetched_opcode = icache_rdata_i[6:0];
  wire is_branch_or_jump = (fetched_opcode == 7'b1100011) ||  // B-type branch
                           (fetched_opcode == 7'b1101111) ||  // JAL
                           (fetched_opcode == 7'b1100111);    // JALR

  // Determine if we should use BTB prediction
  // Only predict taken if BTB hit AND it's a branch/jump instruction
  wire use_btb_prediction = btb_lookup_hit_i && btb_lookup_taken_i && is_branch_or_jump;

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
      pc_q           <= 32'h0000_0000;
      req_pending    <= 1'b0;
      req_pc         <= 32'h0;

      out_valid      <= 1'b0;
      out_pc         <= 32'h0;
      out_instr      <= 32'h0;
      out_pred_taken <= 1'b0;
      out_pred_target<= 32'h0;
    end else begin
      if (flush_i) begin
        pc_q           <= flush_pc_i;
        req_pending    <= 1'b0;
        out_valid      <= 1'b0;
        out_pred_taken <= 1'b0;
        out_pred_target<= 32'h0;
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
          out_valid      <= 1'b1;
          out_pc         <= req_pc;
          out_instr      <= icache_rdata_i;
          out_pred_taken <= use_btb_prediction;
          out_pred_target<= btb_lookup_target_i;

          req_pending <= 1'b0;

          // Next PC: if BTB predicts taken, go to target; else PC+4
          if (use_btb_prediction) begin
            pc_q <= btb_lookup_target_i;
`ifdef FETCH_DEBUG
            $display("[fetch] BTB predicted taken: pc=0x%08x -> target=0x%08x", req_pc, btb_lookup_target_i);
`endif
          end else begin
            pc_q <= req_pc + 32'd4;
          end
        end
      end
    end
  end

endmodule
