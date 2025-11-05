//////////////////////////////////////////////////////////////////////////////////
// Module Name: decode
// Description: Purely combinational instruction decoder (Phase 1)
//   - Supports CA1 subset:
//     {ADDI, LUI, ORI, SLTIU, SRA, SUB, AND, LBU, LW, SH, SW, BNE, JALR}
//   - Determines functional unit (ALU / LSU / BRU)
//   - Unified mapping (ADD == ADDI, etc.) to minimize enumerations
// Additional Comments:
//   - No sequential logic; pipeline/skid regs outside
//////////////////////////////////////////////////////////////////////////////////
module decode #(
  parameter XLEN = 32
)(
  // handshake passthrough
  input  wire        valid_in,
  input  wire [31:0] pc_in,
  input  wire [31:0] instr_in,
  output wire        ready_out,
  output wire        valid_out,
  output wire [31:0] pc_out,

  // register fields
  output wire [4:0]  rs1,
  output wire [4:0]  rs2,
  output wire [4:0]  rd,

  // decoded control
  output reg  [XLEN-1:0] imm,
  output reg             imm_used,
  output reg  [1:0]      fu_type,       // 0=ALU,1=LSU,2=BRU
  output reg  [3:0]      alu_op,        // shared R/I encoding
  output reg             rd_used,
  output reg             is_load,
  output reg             is_store,
  output reg  [1:0]      ls_size,       // 0=byte,1=half,2=word
  output reg             unsigned_load, // for LBU
  output reg             is_branch,     // BNE
  output reg             is_jump        // JALR
);

  // handshake passthrough
  assign ready_out = 1'b1;
  assign valid_out = valid_in;
  assign pc_out    = pc_in;

  // field extraction
  wire [6:0] opcode = instr_in[6:0];
  wire [2:0] funct3 = instr_in[14:12];
  wire       f7bit5 = instr_in[30]; // SUB/SRA flag
  assign rd  = instr_in[11:7];
  assign rs1 = instr_in[19:15];
  assign rs2 = instr_in[24:20];

  // opcode groups
  localparam [6:0] OP_R      = 7'b0110011; // SRA, SUB, AND
  localparam [6:0] OP_I      = 7'b0010011; // ADDI, ORI, SLTIU
  localparam [6:0] OP_LUI    = 7'b0110111;
  localparam [6:0] OP_LOAD   = 7'b0000011; // LBU, LW
  localparam [6:0] OP_STORE  = 7'b0100011; // SH, SW
  localparam [6:0] OP_BRANCH = 7'b1100011; // BNE
  localparam [6:0] OP_JALR   = 7'b1100111; // JALR

  // immediates
  wire [31:0] imm_i = {{20{instr_in[31]}}, instr_in[31:20]};
  wire [31:0] imm_s = {{20{instr_in[31]}}, instr_in[31:25], instr_in[11:7]};
  wire [31:0] imm_b = {{19{instr_in[31]}}, instr_in[31], instr_in[7],
                       instr_in[30:25], instr_in[11:8], 1'b0};
  wire [31:0] imm_u = {instr_in[31:12], 12'b0};

  // ALU opcodes
  localparam [3:0] ALU_ADD  = 4'd0,
                   ALU_SUB  = 4'd1,
                   ALU_AND  = 4'd2,
                   ALU_OR   = 4'd3,
                   ALU_SLTU = 4'd4,
                   ALU_SRA  = 4'd5,
                   ALU_PASS = 4'd15;

  // combinational decode
  always @* begin
    // defaults
    fu_type       = 2'd0;
    alu_op        = ALU_ADD;
    imm           = 32'd0;
    imm_used      = 1'b0;
    rd_used       = 1'b0;
    is_load       = 1'b0;
    is_store      = 1'b0;
    ls_size       = 2'd2;
    unsigned_load = 1'b0;
    is_branch     = 1'b0;
    is_jump       = 1'b0;

    case (opcode)
      // ---------- ALU ----------
      OP_R: begin
        fu_type = 2'd0; rd_used = 1'b1;
        case (funct3)
          3'b101: alu_op = ALU_SRA;                         // SRA
          3'b000: alu_op = (f7bit5 ? ALU_SUB : ALU_ADD);    // SUB/ADD
          3'b111: alu_op = ALU_AND;                         // AND
          default: alu_op = ALU_ADD;
        endcase
      end

      OP_I: begin
        fu_type = 2'd0; rd_used = 1'b1; imm_used = 1'b1; imm = imm_i;
        case (funct3)
          3'b000: alu_op = ALU_ADD;   // ADDI
          3'b110: alu_op = ALU_OR;    // ORI
          3'b011: alu_op = ALU_SLTU;  // SLTIU
          default: alu_op = ALU_ADD;
        endcase
      end

      OP_LUI: begin
        fu_type = 2'd0; rd_used = 1'b1; imm_used = 1'b1;
        imm = imm_u; alu_op = ALU_PASS;
      end

      // ---------- LSU ----------
      OP_LOAD: begin
        fu_type  = 2'd1; rd_used = 1'b1; imm_used = 1'b1; imm = imm_i; is_load = 1'b1;
        case (funct3)
          3'b100: begin ls_size = 2'd0; unsigned_load = 1'b1; end // LBU
          3'b010: begin ls_size = 2'd2; unsigned_load = 1'b0; end // LW
          default: begin ls_size = 2'd2; unsigned_load = 1'b0; end
        endcase
      end

      OP_STORE: begin
        fu_type = 2'd1; imm_used = 1'b1; imm = imm_s; is_store = 1'b1;
        case (funct3)
          3'b001: ls_size = 2'd1; // SH
          3'b010: ls_size = 2'd2; // SW
          default: ls_size = 2'd2;
        endcase
      end

      // ---------- BRU ----------
      OP_BRANCH: begin
        if (funct3 == 3'b001) begin // BNE
          fu_type   = 2'd2;
          imm_used  = 1'b1;
          imm       = imm_b;
          is_branch = 1'b1;
        end
      end

      // ---------- JUMP ----------
      OP_JALR: begin
        fu_type  = 2'd2; rd_used = 1'b1; imm_used = 1'b1;
        imm = imm_i; is_jump = 1'b1;
      end

      default: ; // keep defaults
    endcase
  end

endmodule
