module mac(
    input   wire clk,
    input   wire arst_n,

    input   wire [7:0] A_Feature,
    input   wire [7:0] A_Weight,
    input   wire [7:0] A_Bias,
    input   wire       valid, 
    input   wire       clear,

    input   wire       out_sel,
    output  reg [15:0] selected_output
);

wire signed [7:0] A_Feature_wire;
wire signed [7:0] A_Weight_wire;
wire signed [7:0] A_Bias_wire;
reg signed [31:0] accumulator_reg, accumulator_next;  //increased to 24 bits for overflow detection 
wire signed [15:0] multiplier_prdt;
reg bias_added;

//signed 
assign A_Feature_wire = signed'(A_Feature);
assign A_Weight_wire = signed'(A_Weight);
assign A_Bias_wire = signed'(A_Bias);

//logic 
assign multiplier_prdt = A_Feature_wire * A_Weight_wire;

always@( posedge clk or negedge arst_n) begin 
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
                    accumulator_reg <= accumulator_reg + 32'(A_Bias_wire);
                    bias_added <= 1;
                end else begin 
                    accumulator_reg <= accumulator_reg + 32'(multiplier_prdt);
                end 
            end 
        end 
    end 
end

always@(*) begin 
    case(out_sel) 
        1'b0: selected_output = accumulator_reg[15:0]; 
        1'b1: selected_output = accumulator_reg[31:16]; 
    endcase
end 

endmodule 