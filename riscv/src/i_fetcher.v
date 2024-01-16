module InstructionFetch (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire RoB_clear,
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire pc_change_flag, // <output from decoder, together with RoB_clear>
    input wire [31:0] pc_change_value, 

    input wire stall,  // <output from decoder>
    input wire ready_in,
    input wire [31:0] inst_in,  

    input wire [31:0] RoB_clear_pc_value,

    output wire ready_out,  
    output wire [31:0] inst_out,  
    output wire [31:0] pc_out,  // program counter
    output reg [31:0] addr  
);

    reg [31:0] pc;
    assign ready_out = ready_in && !stall;
    assign inst_out = inst_in;
    assign pc_out = pc;

    always @(posedge clk_in) begin
        if (rst_in) begin            
            pc <= 0;
            addr <= 0;
        end
        else if (rdy_in) begin
            if (RoB_clear) begin
                pc <= RoB_clear_pc_value;
                addr <= RoB_clear_pc_value;
            end
            else begin                            
                if (!pc_change_flag) begin                
                    if (!stall && ready_in) begin
                        pc <= pc + 4;            
                        addr <= pc;    
                    end
                end
                else begin
                    pc <= pc_change_value;
                    addr <= pc;
                end
            end
        end        
    end

endmodule
