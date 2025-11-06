# Verilog CPU — Phase 0 & Phase 1

This repo contains my implementations for the **Verilog CPU project**, including Phase 0 and Phase 1.

---

## Phase 0 — Foundational Modules

### Implemented modules
- `fifo.sv`
- `priority_decoder.sv`
- `skid_buffer_struct.sv`

Each module includes a **self-checking testbench** under `tb/`.

### How to simulate
Open Vivado → Add `src/` as **Design Sources** and `tb/` as **Simulation Sources** →  
Right-click any testbench (e.g. `tb_fifo.sv`) → **Set as Top** → **Run Simulation**.

### Team notes
For Phase 0, my teammate and I worked **individually** to get comfortable with Vivado, simulation setup, and project workflow.  
Starting from **Phase 1**, we began collaborating on design and verification.

---

## Phase 1 — I-Cache, Fetch, and Decode Integration

### Overview
Phase 1 integrates the **instruction fetch path** of the CPU:
- Added a BRAM-based **Instruction Cache (ROM)** with 1-cycle latency.  
- Connected **Fetch → Decode** through a skid buffer.  
- Implemented a demo-style **JALR redirect** to verify control-flow changes.  
- Verified correct alignment between **PC** and **instruction data** in simulation.

### Key files
- `src/icache.sv` — Synchronous BRAM instruction memory using `$readmemh`.  
- `src/top.sv` — Integrates I-Cache, Fetch, Decode, and redirect logic.  
- `tb/tb_top.sv` — Testbench connecting all modules and printing decoded output.  
- `mem/program.hex` — Example instruction memory contents.

### How to simulate
1. Ensure the instruction file is located at:  
mem/program.hex
2. Open Vivado → Add `src/` and `tb/` → Set `tb_top.sv` as **Top**.  
3. Run **Behavioral Simulation**.  
4. Expected trace:  
PC=00000000 INSTR=00000013 fu=0 alu=0 ld=0 st=0 br=0 j=0
PC=00000004 INSTR=00000013 fu=0 alu=0 ld=0 st=0 br=0 j=0
PC=00000008 INSTR=00000013 fu=0 alu=0 ld=0 st=0 br=0 j=0
PC=0000000c INSTR=00008067 fu=2 alu=0 ld=0 st=0 br=0 j=1
PC=00000020 INSTR=12345037 fu=0 alu=15 ld=0 st=0 br=0 j=0
PC=00000028 INSTR=00136313 fu=0 alu=3 ld=0 st=0 br=0 j=0


- The **JALR** at `0x0C` redirects to `0x20`.  
- Subsequent **LUI** and **ORI** instructions decode correctly.

### Notes
- All paths were reverted to **`../mem/program.hex`** for portability.  
- I-Cache acts as **ROM** (read-only, preloaded at elaboration).  
- Fetch produces one word per cycle; Decode is purely combinational.  
- Skid buffers maintain pipeline handshake safety.
