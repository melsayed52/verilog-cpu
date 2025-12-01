# Out-of-Order RISC-V CPU (ECE 189) — Phase 0 → Phase 3

This repository contains my complete implementation of the class Out-of-Order CPU project, including all modules from **Phase 0, Phase 1, Phase 2 (Rename & Dispatch), and Phase 3 (Execute, Writeback, Commit)**.

All code is written in **SystemVerilog** (with a few legacy Verilog files kept for reference).

---

# Repository Structure

/src
├── *.sv ← Phase 3 design sources (top_phase3 and all RTL)
├── extra/ ← Legacy Phase 1 / Phase 2 tops & unused helpers
├── mem/ ← program.hex / data.hex used by testbenches
/tb
├── tb_top_phase0.sv ← (optional) older testbenches
├── tb_top_phase2.sv ← Phase 2 top-level testbench
├── tb_top_phase3.sv ← Phase 3 full-pipeline testbench
├── extra/ ← Unit tests / experimental benches 



All modules required to compile and run **Phase 3** are placed directly under `src/` for simplicity.  
Older or unused files are moved under `src/extra/` to keep the project readable.

---

# Phase 0 — Foundational Infrastructure

### Implemented Modules
- `fifo.sv`
- `priority_decoder.sv`
- `skid_buffer_struct.sv` *(legacy)*

These are basic hardware building blocks used throughout later phases.

### Testbenches
Located under `tb/` (`tb_fifo.sv`, `tb_priority_decoder.sv`, etc.)  
All Phase 0 benches are **self-checking** and run entirely in behavioral simulation.

---

# Phase 1 — Fetch Path Integration

### Features
- BRAM-backed **Instruction Cache (`icache.sv`)**
- **Fetch** stage implementing PC sequencing  
- **Decode** stage producing architectural operand indices & control bits  
- **Skid buffer** between stages to ensure safe valid-ready handshakes  
- Verified **JALR redirect** logic

### Key Files
- `icache.sv`
- `fetch.sv`
- `decode.v`
- `top_ooo.sv` *(Phase-1 top, now in `src/extra/`)*

### Notes
- I-Cache loads instructions from `mem/program.hex`.  
- All instruction/control signals were validated against expected PC/instr traces.

---

# Phase 2 — Rename, RAT, PRF, Dispatch, ROB Integration

Phase 2 introduced the **core OoO backend infrastructure**:

### Major Components
- **Rename stage (`rename.sv`)**  
  - RAT  
  - Free-list  
  - Physical register allocation  
- **PRF (`prf.sv`)**  
  - 1 CDB write port  
  - Multiple read ports  
  - Valid bit tracking  
- **Reservation Stations (`rs_alu.sv`, `rs_lsu.sv`, `rs_bru.sv`)**  
  - Dependency tracking via wakeup  
  - Issue selection when FU ready  
- **Reorder Buffer (`rob.sv`)**  
  - In-order commit  
  - Tracks old/new physical registers  
- **Dispatch (`dispatch.sv`)**  
  - Allocates ROB entries  
  - Inserts instructions into correct RS  
  - Invalidates PRF dest on dispatch  
  - Handles RS wakeup via CDB

### Phase 2 Testing
- `tb_dispatch.sv`
- `tb_rs_writeback.sv`
- `tb_top_phase2.sv` *(integrated front-to-rename-to-dispatch)*

Phase 2 ends with rename, dispatch, and backend data structures functioning correctly, but without FU execution.

---

# Phase 3 — Execute, Writeback, Commit (Full OoO Pipeline)

This is the **main deliverable** of the repository and includes:

---

## Execution Units

### ALU (`alu_fu.sv`)
- 1-cycle pipeline  
- Handles arithmetic, logical, and shift ops  
- Writes back results & marks ROB completion

### Branch Unit (`branch_fu.sv`)
- Branch condition evaluation  
- Jump target generation  
- Writes link register for jumps  
- Outputs redirect signals (Phase 4 support)

### LSU (`lsu_fu.sv`)
- Load-only for Phase 3  
- Performs address calculation  
- 1-cycle BRAM read via `dmem.sv`  
- Sign/zero extension logic

---

## Data Memory (`dmem.sv`)
- Word-indexed BRAM with 1-cycle latency  
- Preloaded with `data.hex`

---

## Common Data Bus (CDB) — `cdb_arbiter.sv`
- Merges FU writebacks  
- Priority: **ALU > LSU > BRU**  
- Feeds PRF + RS wakeup

---

## Commit Stage — `commit_unit.sv`
- Always ready (Phase 3)  
- Reads ROB commit output and frees old physical registers  
- Outputs commit debug info

---

## Top-Level Integration — `top_phase3.sv`
Wires the entire pipeline:

ICache → Fetch → Decode → Rename → Dispatch
→ RS → {ALU, LSU, BRU}
→ CDB → PRF & Wakeup
→ ROB → Commit 



It includes:
- PRF muxing for FU read ports  
- ROB completion plumbing  
- LSU memory interface  
- Full valid-ready handshake between all stages

---

## Phase 3 Testbench — `tb_top_phase3.sv`
- Instantiates `top_phase3.sv`  
- Drives clock/reset  
- Loads program/data memories  
- Runs instructions through the full OoO pipeline  
- Monitors:
  - Issue events  
  - Writeback  
  - ROB commit  
  - Architectural correctness (based on program.hex)

---

# Notes for Graders / Viewers

- `src/extra/` contains **older phases**, alternative tops, and unused structures preserved for reference.
- The main deliverable is **Phase 3** and is fully contained in `src/`.
