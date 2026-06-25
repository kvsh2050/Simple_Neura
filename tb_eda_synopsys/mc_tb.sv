`timescale 1ns/ps

//Interface Definition 

interface mac_if (input logic clk);
    logic       arst_n;
    logic [7:0] A_Feature;
    logic [7:0] A_Weight;
    logic [7:0] A_Bias;
    logic valid;
    logic clear;
    logic [1:0] out_sel;
    logic [7:0] selected_output;
endinterface

//Transaction class: Creates the Array of features, weights, biases
class mac_sequence_item;
    rand int array_size; //array size or total features and weights
    //Dynamic array 
    rand bit signed [7:0] feature_array[];
    rand bit signed [7:0] weight_array[];
    rand bit signed [7:0] bias_val; // Bias is added once per stream

    //CONSTRAINT 1
    constraint arr_size {
        array_size inside {[5:20]};  //5-20 iterations
    }

    //CONSTRAINT 2
    constraint c_arrays{
        feature_array.size() = array_size;
        weight_array.size() = array_size;
    }

    //CONSTRAINT 3
    constraint c_data {
        foreach (feature_array[i]){
            feature_array[i] inside {8'sh7F, 8'sh80, 8'sh00, [-20:20]};
        }
        foreach (weight_array[i]) {
                weight_array[i]  inside {8'sh7F, 8'sh80, 8'sh00, [-5:5]};
            }
        bias_val inside {[-10:10]};
    }

    function void print();
        $$display("[SEQ] Generated dynamic stream of size: %0d (Bias: %0d)", array_size, bias_val);
    endfunction

endclass

//Driver class
class mac_driver;
    virtual mac_if vif;

    function new(virtual  mac_if vif);
        this.vif = vif;
    endfunction

    task drive_item (mac_sequence_item item);
        $display("[DRV] Driving stream into MAC...");
        // 1. Issue a Clear cycle to reset the MAC state machine and register
        @(posedge vif.clk);
        #1 
        vif.clear <= 1'b1;
        vif.valid <= 1'b0;

        // 2. Loop through the generated class 
        for (int i = 0; i < item.array_size; i++) begin
            @(posedge vif.clk);
            #1;
            vif.clear <= 1'b0;
            vif.valid <= 1'b1;
            vif.A_Bias <= item.bias_val;
            vif.A_Feature <= item.feature_array[i];
            vif.A_Weight <= item.weight_array[i];
            vif.out_sel  <= 2'b00;    //default monitoring lsb now 
        end 

        @(posedge vif.clk);
        #1;
        vif.valid <= 1'b0;
    endtask 

endclass

//Monitor class

class mac_monitor;
    virtual mac_if vif;

    function void new(virtual mac_if vif);
        this.vif = vif;
    endfunction

    task run();
        forever begin 
            @(posedge vif.clk);
            if(vif.valid && !vif.clear) begin 
                #2;
                $display("[MON] Inputs Observed -> Feat: %0d | Wght: %0d | Bias: %0d || Mux Output (LSB): %0d", 
                        $signed(vif.A_Feature), $signed(vif.A_Weight), $signed(vif.A_Bias), $signed(vif.selected_output));
            end 
        end 
    endtask
endclass

//TOP
module tb_mac_top;
    logic clk = 0;
    always #10 clk = ~clk; // 50MHz Clock Generation

    // Instantiate interface
    mac_if inf(clk);

    // Instantiate design under test (DUT)
    mac dut (
        .clk             (inf.clk),
        .arst_n          (inf.arst_n),
        .A_Feature       (inf.A_Feature),
        .A_Weight        (inf.A_Weight),
        .A_Bias          (inf.A_Bias),
        .valid           (inf.valid),
        .clear           (inf.clear),
        .out_sel         (inf.out_sel),
        .selected_output (inf.selected_output)
    );

    // Declare Verification Objects
    mac_sequence_item seq_item;
    mac_driver        driver;
    mac_monitor       monitor;

    initial begin
        // Construct execution blocks
        driver  = new(inf);
        monitor = new(inf);
        
        // Fork off monitor to run continuously in background
        fork
            monitor.run();
        join_none

        // Initialize HW System Reset
        inf.arst_n <= 0;
        inf.clear  <= 0;
        inf.valid  <= 0;
        #40;
        inf.arst_n <= 1; // Release asynchronous reset

        // Run 3 independent dynamic matrix size streaming runs
        repeat (3) begin
            seq_item = new();
            if (!seq_item.randomize()) begin
                $fatal("[ERR] Array size/data randomization failed.");
            end
            seq_item.print();
            
            // Send the randomized vector arrays block to the driver
            driver.drive_item(seq_item);
            repeat(3) @(posedge clk); // Idle cushion between matrix blocks
        end

        $display("[TB] All matrix streams parsed. Ending Simulation.");
        $finish;
    end

    // Waveform engine setup for Synopsys VCS on EDA Playground
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_mac_top);
    end

endmodule