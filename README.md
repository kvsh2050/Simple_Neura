# 🧠 Neural Accelerator — Multiply and Accumulate (MAC) Unit

> A hardware-based neural network accelerator built around a dedicated MAC datapath, designed for efficient dot-product computation in silicon.

---

## 📌 Table of Contents

- [Overview](#overview)
- [Why Hardware Acceleration?](#why-hardware-acceleration)
- [MAC Unit Architecture](#mac-unit-architecture)
- [Dataflow & Operation](#dataflow--operation)
- [Temporal Execution Example](#temporal-execution-example)
- [RTL Coding Guidelines](#rtl-coding-guidelines)
- [Future Extensions](#future-extensions)

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

The MAC unit computes the **dot product** between input activations and neural network weights.

### Dataflow Diagram

```
               valid
                 │
                 ▼
Feature ──► [ MAC CELL ] ◄── Weight / Bias
                 │
                 ▼
           Accumulator
                 │
                 ▼
           Output Result
```

### Execution Rule

For every neuron, the MAC loop runs exactly $N$ times (one per input channel):

```
for i = 0 to N-1:
    accumulator += input[i] * weight[i]
```

The hardware simply replaces this software loop with a dedicated datapath — no instruction fetch, no branch overhead.

---

## Dataflow & Operation

### Signal Description

| Signal  | Direction | Description |
|---------|-----------|-------------|
| `clk`   | Input     | Global clock |
| `rst_n` | Input     | Active-low asynchronous reset |
| `valid` | Input     | Indicates valid input data |
| `clr`   | Input     | Clears the accumulator |
| `A`     | Input     | Input activation |
| `B`     | Input     | Weight |
| `out`   | Output    | Accumulated result |

---

## Temporal Execution Example

A single MAC unit can process multiple inputs over time. Below is a 2-input perceptron example:

$$X = \begin{bmatrix} x_{11} & x_{12} \\ x_{21} & x_{22} \end{bmatrix}, \quad W = \begin{bmatrix} w_1 \\ w_2 \end{bmatrix}$$

### Sample 1 — Cycles 1–3

| Cycle | A | B | valid | clr | Accumulator |
|-------|---|---|-------|-----|-------------|
| 1 | $x_{11}$ | $w_1$ | 1 | 0 | $x_{11}w_1$ |
| 2 | $x_{21}$ | $w_2$ | 1 | 0 | $x_{11}w_1 + x_{21}w_2$ |
| 3 | — | — | 0 | 1 | **Read $Y_1$, then clear** |

$$Y_1 = x_{11}w_1 + x_{21}w_2$$

### Sample 2 — Cycles 4–6

| Cycle | A | B | valid | clr | Accumulator |
|-------|---|---|-------|-----|-------------|
| 4 | $x_{12}$ | $w_1$ | 1 | 0 | $x_{12}w_1$ |
| 5 | $x_{22}$ | $w_2$ | 1 | 0 | $x_{12}w_1 + x_{22}w_2$ |
| 6 | — | — | 0 | 1 | **Read $Y_2$, then clear** |

$$Y_2 = x_{12}w_1 + x_{22}w_2$$

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
| ➕ Bias addition | Dedicated bias accumulation path |
| 🧠 Weight memory interface | On-chip SRAM for weight storage |
| 🚀 DMA streaming | High-bandwidth input data streaming |
| 🏭 Fully pipelined engine | End-to-end pipelined inference datapath |

---

## License

This project is open hardware. See [LICENSE](LICENSE) for details.
