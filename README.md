# 🧠 Neural Accelerator — Multiply and Accumulate (MAC) Unit

> A Multiply and Accumulate Engine 

---

## Overview

This project implements a **Neural Accelerator** that performs the core neural network computation entirely in dedicated hardware:

$$\text{Output} = \sum_{i=0}^{N-1} \text{Input}_i \times \text{Weight}_i$$

Instead of relying on a CPU to execute repeated load–multiply–accumulate instructions, this design streams data through a purpose-built datapath, enabling:

- ⚡ Higher throughput
- 🔋 Lower power consumption
- 🔄 Pipelined, parallel execution
- 📦 Efficient data reuse

---

## Why Hardware Acceleration?

On a conventional processor, computing a single neuron with $N$ inputs requires:

| Step | CPU Operation |
|------|--------------|
| 1 | Fetch input feature from memory |
| 2 | Fetch corresponding weight from memory |
| 3 | Multiply |
| 4 | Accumulate into register |
| 5 | Repeat $N$ times |

This sequential loop results in high latency, many memory accesses, and repeated instruction overhead — especially costly for large layers.

The MAC accelerator replaces this loop with a dedicated hardware datapath:

```
CPU:        load → multiply → add → repeat
Hardware:   stream data → continuous MAC operation → output
```

---

## MAC Unit Architecture

### Core Operation

The MAC unit computes the **signed dot product** between 8-bit input activations and weights, with a one-time bias injection per accumulation window. The accumulator is widened to **24 bits** to handle overflow across many accumulation cycles:

$$\text{Output} = \text{Bias} + \sum_{i=0}^{N-1} \text{Feature}_i \times \text{Weight}_i$$

### Internal Datapath

```
 A_Feature [7:0] ──────────────────────────────────────────────────────┐
                                                                        │
 A_Weight  [7:0] ──────────────────────────────────────────────────────┤
                                                          signed extend │
                                              ┌──────────────────────┐ │
                                              │  16-bit Multiplier   │◄┘
                                              │  (multiplier_prdt)   │
                                              └──────────┬───────────┘
                                                         │  [15:0]
                                                         │ sign-extend to 24-bit
 A_Bias [7:0] ──► (only Cycle 0, bias_added=0) ──────►  ▼
                                                    ┌─────────────┐
                                              ┌────►│   Adder     │
                                              │     └──────┬──────┘
                                              │            │
                                              │     ┌──────▼──────┐   arst_n / clear
                                              │     │  24-bit     │◄──────────────────
                                              └─────│ Accumulator │
                                                    └──────┬──────┘
                                                           │ [23:0]
                                                     ┌─────▼──────┐
                                          out_sel ──►│  Output    │──► selected_output [7:0]
                                                    └─────┬──────┘
                                                          └────────────────────────────► out [23:0]
```

### Key Design Decisions

| Decision | Detail |
|----------|--------|
| **Signed arithmetic** | All operands cast via `signed'(...)` — supports negative activations and weights (two's complement) |
| **16-bit product** | `8 × 8` signed multiplication produces a 16-bit intermediate result (`multiplier_prdt`) |
| **24-bit accumulator** | Prevents overflow when accumulating many products; gives 8 guard bits beyond the 16-bit product |
| **One-shot bias** | `bias_added` flag ensures bias is injected exactly once per accumulation window, on the first valid cycle |

### `out_sel` Output Mux

| `out_sel` | `selected_output` | Byte lane |
|-----------|-------------------|-----------|
| `2'b00`   | `accumulator[7:0]`   | Low byte  |
| `2'b01`   | `accumulator[7:0]`   | Low byte  |
| `2'b10`   | `accumulator[15:8]`  | Mid byte  |
| `2'b11`   | `accumulator[23:16]` | High byte |

### Execution Rule

For every neuron, the MAC loop runs exactly $N$ times (one per input channel). Bias is only added on the **first** valid cycle of each window:

```
cycle 0  (valid=1, bias_added=0):  acc = acc + Feature×Weight + Bias   → bias_added = 1
cycle 1+ (valid=1, bias_added=1):  acc = acc + Feature×Weight
...
clear=1:                            acc = 0, bias_added = 0
```

---

## Port Reference

| Signal            | Width  | Direction | Description |
|-------------------|--------|-----------|-------------|
| `clk`             | 1      | Input     | Global clock |
| `arst_n`          | 1      | Input     | Active-low **asynchronous** reset |
| `A_Feature`       | 8      | Input     | Signed input activation (two's complement) |
| `A_Weight`        | 8      | Input     | Signed weight (two's complement) |
| `A_Bias`          | 8      | Input     | Signed bias — injected once per window |
| `valid`           | 1      | Input     | Enables accumulation this cycle |
| `clear`           | 1      | Input     | Synchronously resets accumulator and `bias_added` |
| `out_sel`         | 2      | Input     | Selects 8-bit byte lane from 24-bit accumulator |
| `selected_output` | 8      | Output    | Selected byte lane of accumulator |
| `out`             | 24     | Output    | Full 24-bit accumulator value |

---

## RTL Coding Guidelines

This project targets the **SKY130** standard cell library and follows strict synchronous RTL practices for reliable synthesis and timing closure via OpenLane.

---

### 1 — Single Clock Domain

All sequential logic uses the global clock edge. Mixed clock domains are not permitted.

```verilog
always @(posedge clk) begin
    // synchronous logic only
end
```

---

### 2 — No Gated Clocks

Avoid generating clocks from combinational logic. Use synchronous clock enables instead.

```verilog
// ❌ Avoid
wire my_clk = clk & enable;

// ✅ Correct
always @(posedge clk) begin
    if (!rst_n)    reg_data <= 0;
    else if (en)   reg_data <= next_data;
end
```

---

### 3 — Active-Low Asynchronous Reset

All registers use active-low asynchronous reset to match SKY130 cell primitives.

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)   data <= 0;
    else          data <= next_data;
end
```

---

### 4 — No Internal Tri-State Logic

Internal tri-states are not synthesis-friendly. Use multiplexers instead.

```verilog
// ❌ Avoid
assign data = enable ? value : 1'bz;

// ✅ Correct
assign data = enable ? value : 0;
```

Tri-state buffers are only permitted at top-level I/O pads (`uio_out`, `uio_oe`).

---

### 5 — Fully Specify Combinational Logic

Every combinational `always @*` block must assign outputs in every branch to prevent latch inference.

```verilog
// ✅ Correct — fully specified
always @* begin
    if (enable)   out = a;
    else          out = b;
end

// ❌ Incomplete — may infer latch
always @* begin
    if (enable)   out = data;
    // missing else → latch!
end
```

---

### 6 — Arithmetic Inference

Write arithmetic naturally. Yosys infers optimized multipliers and adder trees automatically.

```verilog
assign result = A * B;   // synthesizer infers hardware multiplier
```

Manual gate-level multiplication is unnecessary.

---

### 7 — Pipeline for Timing Closure

If the critical path is too long, register intermediate results to reduce combinational depth.

```
Without pipeline:          With pipeline:
  Input                      Input
    │                          │
  Multiply                   Multiply ──► Register
    │                                        │
  Accumulate                            Accumulate
    │                                        │
  Output                             Output Register
```

---

## Future Extensions

| Feature | Description |
|---------|-------------|
| 🔀 Parallel MAC array | Multiple MAC units for simultaneous computation |
| 🏗️ Systolic array | Scalable 2D mesh for matrix operations |
| ⚡ Activation functions | ReLU, sigmoid, tanh in hardware |
| 🧠 Weight memory interface | On-chip SRAM for weight storage |
| 🚀 DMA streaming | High-bandwidth input data streaming |
| 🏭 Fully pipelined engine | End-to-end pipelined inference datapath |

---

## License
no License.
