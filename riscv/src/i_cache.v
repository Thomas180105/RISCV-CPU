//This module does not implement read miss handling
module InstructionCache #(
    parameter IndexBit = 2
) (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire wr,       // write/read signal (1 for write)
    input wire waiting,  
    input wire [31:0] addr, 
    input wire [31:0] value,  // value to write

    output wire hit,  
    output wire [31:0] result  
);

    localparam lines = 1 << IndexBit;             //localparam : Parameters localized inside the module
    localparam TagBit = 32 - IndexBit - 2;

    //addr[31:0] : tag[31:4] + index[3:2] + offset[1:0]
    //index to choose the cacheBlock(cacheLine if direct-mapped cache, just like this one)
    //tag to check if the cacheBlock is the one we want
    //offset to choose the byte in the cacheBlock(not ueed in this module since each time we read 4 byte)

    wire [TagBit-1:0] tag = addr[31:2+IndexBit];
    wire [IndexBit-1:0] index = addr[1+IndexBit:2];

    reg valid[lines-1:0];
    reg [TagBit-1:0] tags[lines-1:0];
    reg [31:0] data[lines-1:0];

    assign hit = valid[index] && tags[index] == tag;
    assign result = data[index];
    
    integer i;
    
    always @(posedge clk_in) begin
        if (rst_in) begin
            for (i = 0; i < lines; i = i + 1) begin
                valid[i] <= 0;
                tags[i]  <= 0;
                data[i] <= 0;
            end
        end
        else if (wr) begin            
            valid[index] <= 1;
            tags[index]  <= tag;
            data[index] <= value;
        end
    end

endmodule
