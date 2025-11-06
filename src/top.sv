// top.sv - Phase 1 integration with JALR redirect + skid flush
`timescale 1ns/1ps

module top #(
  parameter int     MEM_DEPTH = 512,
  parameter string  INIT_FILE = "../mem/program.hex",
  parameter         PC_RESET  = 32'h0000_0000
)(
  input  logic clk,
  input  logic rst_n,

  input  logic sink_ready_i,  // tie 1'b1 in Phase 1

  // Fetch observation
  output wire        if_valid_o,
  output wire [31:0] if_pc_o,
  output wire [31:0] if_instr_o,

  // Decode observation
  output wire        dec_valid_o,
  output wire [31:0] dec_pc_o,
  output wire [31:0] dec_instr_o,
  output wire [4:0]  dec_rs1_o,
  output wire [4:0]  dec_rs2_o,
  output wire [4:0]  dec_rd_o,
  output wire [31:0] dec_imm_o,
  output wire [1:0]  dec_fu_type_o,
  output wire [3:0]  dec_alu_op_o,
  output wire        dec_is_load_o,
  output wire        dec_is_store_o,
  output wire        dec_is_branch_o,
  output wire        dec_is_jump_o
);

  // -----------------------------
  // I-CACHE
  // -----------------------------
  wire [31:2] ic_index;
  wire        ic_en;
  wire [31:0] ic_rdata;
  wire        ic_rvalid;

  icache #(
    .MEM_DEPTH(MEM_DEPTH),
    .INIT_FILE(INIT_FILE)
  ) I_ICACHE (
    .clk    (clk),
    .rst_n  (rst_n),
    .index  (ic_index),
    .en     (ic_en),
    .rdata  (ic_rdata),
    .rvalid (ic_rvalid)
  );

  // -----------------------------
  // FETCH (+ redirect)
  // -----------------------------
  wire [31:0] f_pc, f_instr;
  wire        f_valid, f_ready;

  // redirect wires
  wire        redir_valid;
  wire [31:0] redir_target;

  fetch #(
    .PC_RESET(PC_RESET)
  ) I_FETCH (
    .clk            (clk),
    .rst_n          (rst_n),

    .pc_redir_valid (redir_valid),
    .pc_redir_target(redir_target),

    .icache_index   (ic_index),
    .icache_en      (ic_en),
    .icache_rdata   (ic_rdata),
    .icache_rvalid  (ic_rvalid),
    .pc             (f_pc),
    .instr          (f_instr),
    .valid          (f_valid),
    .ready          (f_ready)
  );

  // -----------------------------
  // SKID #1 (Fetch -> Decode), bundle {pc,instr}
  // -----------------------------
  localparam int IF_BUS_W = 64;
  wire [IF_BUS_W-1:0] if_bus_in  = {f_pc, f_instr};
  wire [IF_BUS_W-1:0] if_bus_out;
  wire                if_valid, if_ready;

  skidbuffer #(.DATA_WIDTH(IF_BUS_W)) I_SKID_IF (
    .clk       (clk),
    .rst_n     (rst_n),
    .flush_i   (redir_valid),   // FLUSH on redirect
    .valid_in  (f_valid),
    .ready_in  (f_ready),
    .data_in   (if_bus_in),
    .valid_out (if_valid),
    .ready_out (if_ready),
    .data_out  (if_bus_out)
  );

  assign {if_pc_o, if_instr_o} = if_bus_out;
  assign if_valid_o            = if_valid;

  // Phase 1: decode never back-pressures
  assign if_ready = 1'b1;

  // -----------------------------
  // DECODE (combinational)
  // -----------------------------
  wire        d_valid_out;
  wire [31:0] d_pc_out;
  wire [4:0]  rs1, rs2, rd;
  wire [31:0] imm;
  wire [1:0]  fu_type;
  wire [3:0]  alu_op;
  wire        imm_used, rd_used, is_load, is_store, unsigned_load, is_branch, is_jump;
  wire [1:0]  ls_size;

  decode I_DECODE (
    .valid_in  (if_valid),
    .pc_in     (if_pc_o),
    .instr_in  (if_instr_o),
    .ready_out (),
    .valid_out (d_valid_out),
    .pc_out    (d_pc_out),
    .rs1       (rs1),
    .rs2       (rs2),
    .rd        (rd),
    .imm       (imm),
    .imm_used  (imm_used),
    .fu_type   (fu_type),
    .alu_op    (alu_op),
    .rd_used   (rd_used),
    .is_load   (is_load),
    .is_store  (is_store),
    .ls_size   (ls_size),
    .unsigned_load(unsigned_load),
    .is_branch (is_branch),
    .is_jump   (is_jump)
  );

  // -----------------------------
  // SKID #2 (decoded bundle -> sink)
  // -----------------------------
  localparam int DEC_BUS_W = 121;
  wire [DEC_BUS_W-1:0] dec_bus_in  = {
    d_pc_out,            // 32
    if_instr_o,          // 32
    rs1, rs2, rd,        // 15
    imm,                 // 32
    fu_type,             // 2
    alu_op,              // 4
    is_load,             // 1
    is_store,            // 1
    is_branch,           // 1
    is_jump              // 1
  };

  wire [DEC_BUS_W-1:0] dec_bus_out;

  skidbuffer #(.DATA_WIDTH(DEC_BUS_W)) I_SKID_DEC (
    .clk       (clk),
    .rst_n     (rst_n),
    .flush_i   (redir_valid),   // FLUSH on redirect
    .valid_in  (d_valid_out),
    .ready_in  (),
    .data_in   (dec_bus_in),
    .valid_out (dec_valid_o),
    .ready_out (sink_ready_i),
    .data_out  (dec_bus_out)
  );

  // Unpack
  assign dec_pc_o        = dec_bus_out[DEC_BUS_W-1            -: 32];
  assign dec_instr_o     = dec_bus_out[DEC_BUS_W-1-32         -: 32];
  assign dec_rs1_o       = dec_bus_out[DEC_BUS_W-1-32-32      -: 5];
  assign dec_rs2_o       = dec_bus_out[DEC_BUS_W-1-32-32-5    -: 5];
  assign dec_rd_o        = dec_bus_out[DEC_BUS_W-1-32-32-5-5  -: 5];
  assign dec_imm_o       = dec_bus_out[DEC_BUS_W-1-32-32-5-5-5 -: 32];
  assign dec_fu_type_o   = dec_bus_out[DEC_BUS_W-1-32-32-5-5-5-32 -: 2];
  assign dec_alu_op_o    = dec_bus_out[DEC_BUS_W-1-32-32-5-5-5-32-2 -: 4];
  assign dec_is_load_o   = dec_bus_out[DEC_BUS_W-1-32-32-5-5-5-32-2-4 -: 1];
  assign dec_is_store_o  = dec_bus_out[DEC_BUS_W-1-32-32-5-5-5-32-2-4-1 -: 1];
  assign dec_is_branch_o = dec_bus_out[DEC_BUS_W-1-32-32-5-5-5-32-2-4-1-1 -: 1];
  assign dec_is_jump_o   = dec_bus_out[DEC_BUS_W-1-32-32-5-5-5-32-2-4-1-1-1 -: 1];

  // -----------------------------
  // Redirect policy (demo): one-shot + flush
  // -----------------------------
  reg redir_armed;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      redir_armed <= 1'b1;
    end else begin
      if (dec_valid_o && dec_is_jump_o && redir_armed) begin
        redir_armed <= 1'b0;         // fired once for this beat
      end else if (!dec_valid_o) begin
        redir_armed <= 1'b1;         // re-arm when beat leaves pipeline
      end
    end
  end

  // Guarded redirect:
  // If imm == 0 (e.g., JALR x0,x1,0), jump to 0x20 for demo so we don't loop at pc.
  wire [31:0] jalr_pc_plus_imm = (dec_pc_o + dec_imm_o) & 32'hFFFF_FFFE;
  wire        imm_is_zero      = (dec_imm_o == 32'd0);

  assign redir_valid  = dec_valid_o && dec_is_jump_o && redir_armed;
  assign redir_target = imm_is_zero ? 32'h0000_0020 : jalr_pc_plus_imm;

endmodule
