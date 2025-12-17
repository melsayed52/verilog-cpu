//////////////////////////////////////////////////////////////////////////////////
// Module Name: icache
// Description: Simple synchronous ROM-like i-cache (BRAM-friendly interface).
//              - 1 word per row (32-bit)
//              - synchronous read: rdata/rvalid updated on posedge after en
//
// UPDATED:
//   - Initialize from TWO kinds of .txt files (simulation loader):
//       (A) disassembly txt (objdump-like):
//             "  5c:        0129f9b3        and x19 x19 x18"
//           Loads WORD at (ADDR>>2). Ignores labels like "0000005c <loop0>:"
//       (B) instMem bytes txt:
//             one byte per line, e.g. "37"
//           Packs 4 bytes little-endian into 32-bit words.
//
// DEBUG/ROBUSTNESS:
//   - Prints whether PROGRAM_TXT can be opened.
//   - Optional REQUIRE_FILE: if set, missing file => $fatal (no silent NOPs).
//
// Additional Comments:
//   - Defaults to NOPs if file missing or lines invalid (unless REQUIRE_FILE=1).
//   - Keeps BRAM-like read behavior; only init is simulation parsing.
//   - Bounds checks full (addr>>2) against DEPTH_WORDS before indexing.
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module icache #(
  parameter int    DEPTH_WORDS  = 512,
  parameter string PROGRAM_TXT  = "25test.txt",
  parameter bit    REQUIRE_FILE = 1'b0   // set to 1 to hard-fail if file missing
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic        en,
  input  logic [31:0] addr,
  output logic [31:0] rdata,
  output logic        rvalid
);

  logic [31:0] mem [0:DEPTH_WORDS-1];

  integer i;

  // ------------------------------------------------------------
  // Helpers: ignore blank/comment-only lines
  // ------------------------------------------------------------
  function automatic bit is_ignorable_line(input string s);
    string t;
    int k;
    begin
      t = s;

      // trim leading whitespace
      k = 0;
      while (k < t.len() &&
            (t.getc(k) == " " || t.getc(k) == "\t" ||
             t.getc(k) == "\r" || t.getc(k) == "\n")) begin
        k++;
      end

      if (k >= t.len()) begin
        t = "";
      end else if (k > 0) begin
        t = t.substr(k, t.len()-1);
      end

      if (t.len() == 0) begin
        is_ignorable_line = 1'b1;
      end else if (t.len() >= 1 && t.getc(0) == "#") begin
        is_ignorable_line = 1'b1;
      end else if (t.len() >= 2 && t.getc(0) == "/" && t.getc(1) == "/") begin
        is_ignorable_line = 1'b1;
      end else begin
        is_ignorable_line = 1'b0;
      end
    end
  endfunction

  // ------------------------------------------------------------
  // Loader A: disassembly format "addr: word ..."
  // ------------------------------------------------------------
  task automatic load_disasm_txt(input string fname, output int loaded_words);
    integer fd;
    string  line;
    int     n;
    int unsigned a;
    int unsigned w;
    int unsigned idx;
    begin
      loaded_words = 0;

      fd = $fopen(fname, "r");
      if (fd == 0) begin
        $display("[icache] WARN: could not open disasm file: %s", fname);
        disable load_disasm_txt;
      end

      while (!$feof(fd)) begin
        line = "";
        void'($fgets(line, fd));
        if (is_ignorable_line(line)) continue;

        a = 0;
        w = 0;

        // Matches:
        // "    5c:        0129f9b3        and ..."
        n = $sscanf(line, "%h: %h", a, w);

        if (n == 2) begin
          idx = (a >> 2);
          if (idx < DEPTH_WORDS) begin
            mem[idx] = w[31:0];
            loaded_words++;
          end
        end
        // else: label-only lines like "0000005c <loop0>:" are ignored
      end

      $fclose(fd);
      $display("[icache] Loaded disasm txt: %s (words=%0d)", fname, loaded_words);
    end
  endtask

  // ------------------------------------------------------------
  // Loader B: one byte per line, pack little-endian words
  // ------------------------------------------------------------
  task automatic load_instmem_bytes(input string fname, output int loaded_words);
    integer fd;
    string  line;
    int     n;
    int unsigned b;
    int unsigned word;
    int unsigned byte_count;
    int unsigned word_idx;
    begin
      loaded_words = 0;

      fd = $fopen(fname, "r");
      if (fd == 0) begin
        $display("[icache] WARN: could not open byte file: %s", fname);
        disable load_instmem_bytes;
      end

      word       = 32'h0000_0013;
      byte_count = 0;
      word_idx   = 0;

      while (!$feof(fd)) begin
        line = "";
        void'($fgets(line, fd));
        if (is_ignorable_line(line)) continue;

        b = 0;
        n = $sscanf(line, "%h", b);
        if (n != 1) continue;
        if (b > 8'hFF) continue;

        // pack little-endian: first byte -> [7:0], second -> [15:8], etc.
        case (byte_count)
          0: word[7:0]   = b[7:0];
          1: word[15:8]  = b[7:0];
          2: word[23:16] = b[7:0];
          3: word[31:24] = b[7:0];
        endcase

        byte_count++;

        if (byte_count == 4) begin
          if (word_idx < DEPTH_WORDS) begin
            mem[word_idx] = word[31:0];
            loaded_words++;
          end
          word_idx   = word_idx + 1;
          byte_count = 0;
          word       = 32'h0000_0013;
        end
      end

      // write partial last word if present
      if (byte_count != 0) begin
        if (word_idx < DEPTH_WORDS) begin
          mem[word_idx] = word[31:0];
          loaded_words++;
        end
      end

      $fclose(fd);
      $display("[icache] Loaded instMem-byte txt: %s (words=%0d)", fname, loaded_words);
    end
  endtask

  // ------------------------------------------------------------
  // Auto-detect: sniff, then load; prints what it decided.
  // Also: explicit open check so missing files never fail silently.
  // ------------------------------------------------------------
  task automatic load_program_auto(input string fname);
    integer fd;
    string  line;
    int     n;
    int unsigned a;
    int unsigned w;
    int unsigned b;
    bit     saw_disasm_pair;
    bit     saw_byte;
    int     loaded_a;
    int     loaded_b;
    begin
      saw_disasm_pair = 1'b0;
      saw_byte        = 1'b0;
      loaded_a        = 0;
      loaded_b        = 0;

      // explicit open check
      fd = $fopen(fname, "r");
      if (fd == 0) begin
        if (REQUIRE_FILE) begin
          $fatal(1, "[icache] ERROR: cannot open PROGRAM_TXT='%s'. Add it to sim sources or fix working dir/path.", fname);
        end else begin
          $display("[icache] WARN: cannot open PROGRAM_TXT='%s'. Leaving default NOPs.", fname);
          disable load_program_auto;
        end
      end

      // sniff file by scanning a handful of meaningful lines
      while (!$feof(fd)) begin
        line = "";
        void'($fgets(line, fd));
        if (is_ignorable_line(line)) continue;

        a = 0; w = 0;
        n = $sscanf(line, "%h: %h", a, w);
        if (n == 2) begin
          saw_disasm_pair = 1'b1;
          break;
        end

        b = 0;
        n = $sscanf(line, "%h", b);
        if (n == 1 && b <= 8'hFF) begin
          saw_byte = 1'b1;
          // keep scanning in case we later see disasm
        end
      end

      $fclose(fd);

      if (saw_disasm_pair) begin
        $display("[icache] Detected disasm format for %s", fname);
        load_disasm_txt(fname, loaded_a);
        if (loaded_a == 0 && saw_byte) begin
          $display("[icache] Disasm load wrote 0 words; falling back to byte-pack loader for %s", fname);
          load_instmem_bytes(fname, loaded_b);
        end
      end else if (saw_byte) begin
        $display("[icache] Detected byte-per-line format for %s", fname);
        load_instmem_bytes(fname, loaded_b);
      end else begin
        $display("[icache] Could not detect format; trying disasm loader for %s", fname);
        load_disasm_txt(fname, loaded_a);
      end
    end
  endtask

  // ------------------------------------------------------------
  // Init memory
  // ------------------------------------------------------------
  initial begin
    for (i = 0; i < DEPTH_WORDS; i = i + 1) begin
      mem[i] = 32'h0000_0013; // nop
    end

    $display("[icache] init: PROGRAM_TXT='%s' REQUIRE_FILE=%0d", PROGRAM_TXT, REQUIRE_FILE);

    // If your sim is silently not loading, this line will now make it obvious.
    load_program_auto(PROGRAM_TXT);
  end

  // full index (do not truncate high bits before bounds check)
  logic [31:0] word_idx_full;
  assign word_idx_full = addr >> 2;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rdata  <= 32'h0000_0013;
      rvalid <= 1'b0;
    end else begin
      if (en) begin
        if (word_idx_full < DEPTH_WORDS) begin
          rdata <= mem[word_idx_full[$clog2(DEPTH_WORDS)-1:0]];
        end else begin
          rdata <= 32'h0000_0013;
        end
        rvalid <= 1'b1;
      end else begin
        rvalid <= 1'b0;
      end
    end
  end

endmodule
