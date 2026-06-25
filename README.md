# Neural Accelerator : Multiply and Accumulate Project

## Overview

This project focuses on designing a hardware-based **Neural Accelerator** capable of performing neural network computations efficiently using dedicated hardware datapaths.

The primary building block is the **MAC (Multiply-Accumulate) unit**, which performs the core operation used in neural networks:

\[
Output = \sum_{i=0}^{N-1} Input_i \times Weight_i
\]

The accelerator replaces slow sequential CPU execution with a dedicated hardware pipeline that can process multiple operations efficiently.

---

# Why Do We Need a Neural Accelerator?

In a conventional processor, calculating a single neuron requires repeated sequential operations:

1. Fetch an input feature from memory.
2. Fetch the corresponding weight from memory.
3. Perform multiplication.
4. Add the result to an accumulator.
5. Repeat for every input channel.

For a neuron with hundreds of inputs, this results in:

- Many memory accesses.
- Repeated instruction execution.
- High latency.
- Increased power consumption.

A neural accelerator solves this by implementing the computation directly in hardware using:

- Parallel arithmetic units.
- Dedicated datapaths.
- Pipelined execution.
- Efficient data reuse.

Instead of executing:

```

load → multiply → add → repeat

````

on a CPU, the accelerator streams data through hardware and performs the operation continuously.

---

# RTL Coding Guidelines

This project follows strict synchronous RTL design practices to ensure reliable synthesis and timing closure.

---

## 1. Single Clock Domain

All sequential logic must use the global clock.

Use:

    always @(posedge clk)


Every flip-flop in the design must be triggered by the same clock edge.

---

## 2. No Gated Clocks

Do not generate clocks using combinational logic.

Avoid:

    wire my_clk = clk & enable;


Use synchronous clock enables instead:

    always @(posedge clk) begin
        if (!rst_n)
            reg_data <= 0;
        else if (en)
            reg_data <= next_data;
    end


This allows synthesis tools to infer safe clock enable structures.

---

## 3. Reset Style

Use an **active-low asynchronous reset**.

Required format:

    always @(posedge clk or negedge rst_n)


Example:

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            data <= 0;
        else
            data <= next_data;
    end


The SKY130 standard cell library provides optimized resettable flip-flops for this style.

---

## 4. Avoid Internal Tri-State Logic

Do not use:

    assign data = enable ? value : 1'bz;


inside the design.

Internal tri-states are difficult for synthesis tools.

Use multiplexers instead:

    assign data = enable ? value : 0;


Tri-state logic should only exist at the top-level I/O wrapper for pins such as:


    uio_out
    uio_oe


---

## 5. Fully Define Combinational Logic

All combinational blocks must completely specify outputs.

Use:

    always @*


Every conditional must have a complete assignment.

Example:

Correct:

    always @* begin
        if(enable)
            out = a;
        else
            out = b;
    end


Avoid incomplete assignments because synthesis may infer unwanted latches.

---

## 6. Avoid Accidental Latch Inference

If a signal is not assigned in every possible path:

    always @* begin
        if(enable)
            out = data;
    end


the synthesizer may create a transparent latch.

This can cause:

* Timing failures.
* Unpredictable behavior.
* OpenLane placement issues.

---

## 7. Arithmetic Inference

Writing:

    assign result = A * B;


is valid RTL.

Yosys can infer:

* Multipliers.
* Adder trees.
* Optimized arithmetic structures.

Manual gate-level multiplication is unnecessary.

---

## 8. Pipeline for Timing Closure

If timing becomes difficult, divide the computation into pipeline stages.

Example:

Instead of:


    Input
    |
    Multiply
    |
    Accumulate
    |
    Output

use:

    Input
    |
    Multiply Register
    |
    Accumulator
    |
    Output Register


Registering intermediate results reduces the critical path.

---

# MAC Unit Architecture

## Purpose

A MAC unit performs:

\[
Output = \sum_{i=0}^{N-1} Input_i \times Weight_i
\]

It calculates the dot product between:

* Input activations.
* Neural network weights.

---

## MAC Dataflow


                    Valid
                    |
                    v

    Feature ---> [ MAC CELL ] <--- Weight, Bias
                    |
                    |
                    v
                Accumulator
                    |
                    v
                Output Result


   


The MAC unit:

1. Receives input activation.
2. Multiplies activation with weight.
3. Adds result into accumulator.
4. Passes data to the next processing stage.

---

# Processing Neural Network Dimensions

The dimensions of a neural network are handled by scheduling data over time or by using multiple MAC units.

Two approaches exist:

## Temporal Execution

A single MAC processes multiple values over multiple clock cycles.

Example:

A 2-input perceptron:

    Inputs:

    [
    X =
    \begin{bmatrix}
    x_{11} & x_{12}\
    x_{21} & x_{22}
    \end{bmatrix}
    ]

    Weights:

    [
    W =
    \begin{bmatrix}
    w_1\
    w_2
    \end{bmatrix}
    ]

---

## Sample 1 Processing

### Cycle 1

Inputs:

```
A = x11
B = w1
valid = 1
```

MAC computes:

[
x_{11} \times w_1
]

---

### Cycle 2

Inputs:

```
A = x21
B = w2
valid = 1
```

Accumulator becomes:

[
(x_{11}w_1)+(x_{21}w_2)
]

---

### Cycle 3

Output stage:

```
valid = 0
```

The final result is read:

[
Y_1=(x_{11}w_1)+(x_{21}w_2)
]

Then:

```
clr = 1
```

to reset the accumulator.

---

# Sample 2 Processing

### Cycle 4

Inputs:

```
A = x12
B = w1
valid = 1
```

Compute:

[
x_{12}w_1
]

---

### Cycle 5

Inputs:

```
A = x22
B = w2
valid = 1
```

Compute:

[
(x_{12}w_1)+(x_{22}w_2)
]

---

### Cycle 6

Read output:

[
Y_2=(x_{12}w_1)+(x_{22}w_2)
]

Reset accumulator.

---

# Execution Rule

The MAC loop must execute exactly:

[
N = \text{number of input channels}
]

times.

For every neuron:

```
for i = 0 to N-1:

    accumulator += input[i] * weight[i]
```

The hardware implementation simply replaces this software loop with a dedicated datapath.

---

# Future Extensions

Possible improvements:

* Multiple MAC units for parallel execution.
* Systolic array architecture.
* Activation functions (ReLU, sigmoid).
* Bias addition.
* Weight memory interface.
* DMA based streaming input.
* Fully pipelined inference engine.

```
```
