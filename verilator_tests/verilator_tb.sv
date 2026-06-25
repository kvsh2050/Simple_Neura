`timescale 1ns/1ps

class mac_sequence_item;
    int array_size;
    logic signed [7:0] feature_array[];
    logic signed [7:0] weight_array[];
    logic signed [7:0] bias_val;

    function void randomize_stream();
        this.array_size = $urandom_range(5, 12); // Keep sizes predictable
        this.feature_array = new[this.array_size];
        this.weight_array  = new[this.array_size];
        
        foreach (feature_array[i]) begin
            this.feature_array[i] = 8'($urandom_range(1, 50)); // Keep positive for easy sanity debug
            this.weight_array[i]  = 8'($urandom_range(1, 5));
        end
        this.bias_val = 8'($urandom_range(1, 10));
    endfunction

    function void print();
        $display("[SEQ] Stream Size: %0d | Bias: %0d", array_size, bias_val);
    endfunction
endclass

module verilator_tb;

    // Internal signals act as the local testbench wires
    logic       clk;
    logic       arst_n;
    logic [7:0] A_Feature;
    logic [7:0] A_Weight;
    logic [7:0] A_Bias;
    logic       valid;
    logic       clear;
    logic [1:0] out_sel;
    logic [7:0] selected_output;
    logic [23:0] out;

    // Direct local instantiation of your design
    mac dut (
        .clk             (clk),
        .arst_n          (arst_n),
        .A_Feature       (A_Feature),
        .A_Weight        (A_Weight),
        .A_Bias          (A_Bias),
        .valid           (valid),
        .clear           (clear),
        .out_sel         (out_sel),
        .selected_output (selected_output),
        .out             (out)
    );


    mac_sequence_item seq_item;

    initial begin
        arst_n    = 1'b0;
        clear     = 1'b0;
        valid     = 1'b0;
        A_Feature = 8'd0;
        A_Weight  = 8'd0;
        A_Bias    = 8'd0;
        out_sel   = 2'b00;
        
        repeat(5) @(posedge clk);
        arst_n    = 1'b1; // Release reset
        repeat(2) @(posedge clk);
        
        $display("[TB] Starting Verilator Cycle Simulation...");

        repeat (3) begin
            seq_item = new();
            seq_item.randomize_stream();
            seq_item.print();
            
            // 1. Issue Clear
            @(posedge clk);
            clear = 1'b1;
            valid = 1'b0;
            
            // 2. Drive Stream
            for (int i = 0; i < seq_item.array_size; i++) begin
                // Wait for the clock edge to pass completely before changing lines
                @(posedge clk); 
                clear     = 1'b0;
                valid     = 1'b1;
                A_Feature = seq_item.feature_array[i];
                A_Weight  = seq_item.weight_array[i];
                A_Bias    = seq_item.bias_val;
                out_sel   = 2'b00; // Look at LSB
            end
            
            // End of stream packet
            @(posedge clk);
            valid = 1'b0;
            
            // Cycle out_sel through windows at the end of the packet computation block
            @(posedge clk);
            out_sel = 2'b00; // Low Byte
            
            @(posedge clk);
            out_sel = 2'b10; // Middle Byte
            
            repeat(3) @(posedge clk);
        end

        $display("[TB] All streams complete.");
        $finish;
    end

    // Monitor logic: sample right before the next rising clock edge 
    // to give combinational math lines time to resolve
    always @(negedge clk) begin
        if (valid && !clear) begin
            $display("[MON] Feat: %0d | Wght: %0d | Bias: %0d -> Mux Out (out_sel=%b): %0d| Actual output:%d", 
                     $signed(A_Feature), $signed(A_Weight), $signed(A_Bias), out_sel, $signed(selected_output), out);
        end 
    end

    // ============================================================================
    // 6. SCOREBOARD REFERENCE MODEL (Self-Checking Logic)
    // ============================================================================
    logic signed [23:0] golden_accumulator = 24'sh0;
    logic               golden_bias_added  = 1'b0;
    
    // Total Test Counters
    int match_count   = 0;
    int mismatch_count = 0;

    always @(negedge clk) begin
        if (!arst_n) begin
            golden_accumulator <= 24'sh0;
            golden_bias_added  <= 1'b0;
        end else if (clear) begin
            // Replicate clear cycle
            golden_accumulator <= 24'sh0;
            golden_bias_added  <= 1'b0;
        end else if (valid) begin
            // 1. Calculate Golden Reference State
            automatic logic signed [15:0] prod = $signed(A_Feature) * $signed(A_Weight);
            
            if (!golden_bias_added) begin
                golden_accumulator <= golden_accumulator + 24'(prod) + 24'($signed(A_Bias));
                golden_bias_added  <= 1'b1;
            end else begin
                golden_accumulator <= golden_accumulator + 24'(prod);
            end

            // 2. Perform the Check immediately at negedge (after state updates evaluate)
            // We use an automatic variable to capture the NEXT state prediction for immediate cycle match
            begin
                logic signed [23:0] expected_acc;
                logic signed [7:0]  expected_mux_out;
                
                if (!golden_bias_added)
                    expected_acc = golden_accumulator + 24'(prod) + 24'($signed(A_Bias));
                else
                    expected_acc = golden_accumulator + 24'(prod);

                // Select slice based on out_sel configuration
                case (out_sel)
                    2'b00, 2'b01: expected_mux_out = expected_acc[7:0];
                    2'b10:        expected_mux_out = expected_acc[15:8];
                    2'b11:        expected_mux_out = expected_acc[23:16];
                    default:      expected_mux_out = expected_acc[7:0];
                endcase

                // Assertion Check
                if (($signed(selected_output) === expected_mux_out) && (expected_acc == out)) begin
                    $display("[PASS] Feat:%3d | Wght:%2d | Bias:%2d || DUT Out:%4d == Exp Out:%4d || Out:%d == Exp Out:%d", 
                             $signed(A_Feature), $signed(A_Weight), $signed(A_Bias), 
                             $signed(selected_output), expected_mux_out, $signed(out), $signed(expected_acc));
                    match_count++;
                end else begin
                    $error("[FAIL MISMATCH] Feat:%3d | Wght:%2d | Bias:%2d || DUT Out:%4d != Exp Out:%4d (Full Exp Acc: %h)", 
                           $signed(A_Feature), $signed(A_Weight), $signed(A_Bias), 
                           $signed(selected_output), expected_mux_out, expected_acc);
                    mismatch_count++;
                end
            end
        end
    end

    // Print final summary report right before simulation closes down
    final begin
        $display("\n==================================================");
        $display("               SIMULATION REPORT                 ");
        $display("==================================================");
        $display("  TOTAL MATCHES:    %0d", match_count);
        $display("  TOTAL MISMATCHES: %0d", mismatch_count);
        if (mismatch_count == 0) begin
            $display("  STATUS:           PASSED SUCCESSFULY! ");
        end else begin
            $display("  STATUS:           FAILED CODE ERRORS PRESENT ");
        end
        $display("==================================================\n");
    end

endmodule