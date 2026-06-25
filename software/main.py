import numpy as np

# 1. Suppose we have a trained weight vector for 1 neuron with 4 inputs
weights = np.array([0.5, -0.25, 0.75, 0.1], dtype=np.float32)

# 2. Quantization: Convert floating-point numbers to signed integers 
# Quantization scale example for a 6-bit signed integer range (-32 to 31)
SCALE = 32
quantized_weights = np.clip(np.round(weights * SCALE), -32, 31).astype(np.int8)
# Now weights are integers: [16, -8, 24, 3]

# 3. Save as a raw binary file or directly format as a hex list
with open("saves/weights.bin", "wb") as f:
    f.write(quantized_weights.tobytes())