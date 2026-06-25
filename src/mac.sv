module mac(
    input   logic clk,
    input   logic arst_n,

    input   logic [7:0] A_Feature,
    input   logic [7:0] A_Weight,
    input   logic [7:0] A_Bias,
    input   logic       valid, 
    input   logic       clear,

    input   logic [1:0] out_sel,
    output  logic [7:0] selected_output
);

logic signed [7:0] A_Feature_wire;
logic signed [7:0] A_Weight_wire;
logic signed [7:0] A_Bias_wire;
logic signed [23:0] accumulator_reg, accumulator_next;  //increased to 24 bits for overflow detection 
logic signed [15:0] multiplier_prdt;
logic bias_added;

//signed 
assign A_Feature_wire = signed'(A_Feature);
assign A_Weight_wire = signed'(A_Weight);
assign A_Bias_wire = signed'(A_Bias);

//logic 
assign multiplier_prdt = A_Feature_wire * A_Weight_wire;

always_ff @( posedge clk or negedge arst_n) begin 
    if (!arst_n) begin 
        accumulator_reg <= 0;
        bias_added <= 0;
    end else begin 
        if(clear) begin 
            accumulator_reg <= 'b0;
            bias_added <= 0;
        end else begin 
            if (valid) begin 
                if(!bias_added) begin 
                    accumulator_reg <= accumulator_reg + 24'(multiplier_prdt) + 24'(A_Bias_wire);
                    bias_added <= 1;
                end else begin 
                    accumulator_reg <= accumulator_reg + 24'(multiplier_prdt);
                end 
            end 
        end 
    end 
end

always_comb begin 
    case(out_sel) 
        2'b00: selected_output = accumulator_reg[7:0]; 
        2'b01: selected_output = accumulator_reg[7:0]; 
        2'b10: selected_output = accumulator_reg[15:8]; 
        2'b11: selected_output = accumulator_reg[23:16]; 
        default: selected_output = accumulator_reg[7:0]; 
    endcase
end 

endmodule 