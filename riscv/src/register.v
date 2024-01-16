module Register (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signa
    input wire RoB_clear,
    input wire rdy_in,  // ready signal, pause cpu when low

    

    input wire [ 4:0] set_reg,        // RoB execution
    input wire [31:0] set_val,    

    input wire [ 4:0] set_q_index_1,  // q index to be set from issue
    input wire [31:0] set_q_val_1,    // (only [3:0] used)   
    input wire [ 4:0] set_q_index_2,  // q index to be set from commit
    input wire [31:0] set_q_val_2,    // (only [3:0] used)  

    input wire [4:0] get_reg_1,       // <output from decoder i.e. rs1 in instruction>
    input wire [4:0] get_reg_2,  
    output wire [31:0] get_val_1,  
    output wire [31:0] get_val_2,  
    output wire [3:0] get_q_value_1,  // q_i value1
    output wire [3:0] get_q_value_2,  // q_i value2
    output wire       get_q_ready_1,  // q_i ready1
    output wire       get_q_ready_2   // q_i ready2
);

    reg [31:0] regfile[31:0];
    reg [31:0] q[31:0];
    reg ready[31:0];    

    assign get_val_1 = regfile[get_reg_1];
    assign get_val_2 = regfile[get_reg_2];
    assign get_q_value_1 = q[get_reg_1];
    assign get_q_value_2 = q[get_reg_2];
    assign get_q_ready_1 = ready[get_reg_1];    
    assign get_q_ready_2 = ready[get_reg_2];

    integer i;

    always @(posedge clk_in) begin
        if (rst_in || RoB_clear) begin
            for (i = 0; i < 32; i = i + 1) begin
                if (rst_in) begin
                    regfile[i] <= 0;
                end 
                q[i] <= 0;
                ready[i] <= 1'b1;
            end
        end
        else if (rdy_in) begin
            if (set_reg != 0) begin
                regfile[set_reg] <= set_val;
            end
            if (set_q_index_1 != 0) begin
                q[set_q_index_1] <= set_q_val_1;
                ready[set_q_index_1] <= 1'b0;
            end
            if (set_q_index_2 != 0 && set_q_index_2 != set_q_index_1) begin
                if (q[set_q_index_2] == set_q_val_2) begin
                    ready[set_q_index_2] <= 1'b1;
                end                
            end
        end
    end


endmodule
