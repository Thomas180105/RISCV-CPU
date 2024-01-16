module MemoryController (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire RoB_clear,
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire [31:0] value,      // data that will be written to mem in 4 cycles
    input wire [31:0] addr,       // (only 17:0 is used)
    input wire        wr,         // write/read signal (1 for write)
    output wire [ 7:0] mem_dout,  // data output bus
    output wire [31:0] mem_a,     // address bus (only 17:0 is used)
    output wire        mem_wr,    // write/read signal (1 for write)

    input  wire [ 7:0] mem_din,   // data input bus
    output wire [31:0] result,     // result of read operation

    input wire        waiting,    // waiting for work
    input wire [ 2:0] len,        // type，See the sign_extend function for more information.
    output wire       ready      // 1 indicates that the memcontrol is ready to start a new work
);

    // tasks to be accomplished in stages (write data to memory)
    reg         work_wr;
    reg  [ 2:0] work_len;
    reg  [31:0] work_addr;
    reg  [31:0] work_value;

    // tasks to be accomplished in stages (read data from memory)
    reg  [31:0] res;

    // current working
    reg         current_wr;
    reg  [31:0] current_addr;
    reg  [ 7:0] current_value;

    // tags
    wire        need_work;
    wire        first_cycle;
    reg         busy;
    reg  [ 2:0] state;
    

    assign ready = !busy && state == 0 && work_wr == wr && work_len == len && work_addr == addr && work_value == value;
    assign result = sign_extend(len, mem_din, res);

    assign need_work = waiting && !ready; //Conditions for state machine transfer away from state 0
    assign first_cycle = state == 0 && need_work;

    assign mem_wr = first_cycle ? wr : current_wr;
    assign mem_a = first_cycle ? addr : current_addr;
    assign mem_dout = first_cycle ? value[7:0] : current_value;

    always @(posedge clk_in) begin
        if (rst_in || RoB_clear) begin
            work_wr <= 0;
            work_len <= 0;
            work_addr <= 0;
            work_value <= 0;
            busy <= 1;
            state <= 0;
            res <= 0;
            current_wr <= 0;
            current_addr <= 0;
            current_value <= 0;
        end
        else if (rdy_in) begin
            case (state)
                2'b00: begin
                    if (need_work) begin    
                        work_wr <= wr;
                        work_len <= len;
                        work_addr <= addr;
                        work_value <= value;
                        if (len[1:0]) begin
                            state <= 2'b01;
                            busy <= 1;
                            current_wr <= wr;
                            current_addr <= addr + 1;
                            current_value <= value[15:8];
                        end
                        else begin
                            state <= 2'b00;
                            busy <= 0;
                            current_wr <= 0;
                            current_value <= 0;
                            current_addr <= addr[17:16] == 2'b11 ? 0 : addr;
                        end
                    end
                end
                2'b01: begin
                    if (work_len[1:0] == 2'b00) begin
                        state <= 2'b00;
                        busy <= 0;
                        current_wr <= 0;
                        current_value <= 0;
                    end
                    else begin
                        state <= 2'b10;
                        res[7:0] <= mem_din;
                        current_addr <= work_addr + 2;
                        current_value <= work_value[23:16];
                    end
                end
                2'b10: begin
                    if (work_len[1:0] == 2'b01) begin
                        state <= 2'b00;
                        busy <= 0;
                        current_wr <= 0;
                        current_value <= 0;
                    end
                    else begin
                        state <= 2'b11;
                        res[15:8] <= mem_din;
                        current_addr <= work_addr + 3;
                        current_value <= work_value[31:24];
                    end
                end
                2'b11: begin
                    state <= 2'b00;
                    busy <= 0;
                    res[23:16] <= mem_din;
                    current_wr <= 0;
                    current_value <= 0;
                end
            endcase
        end
    end

    // 00: 1 byte, 01: 2 bytes, 10: 4 bytes
    // len[2]: signed or unsigned
    function [31:0] sign_extend;
        input [2:0] len;
        input [7:0] mem_din;
        input [31:0] value;
        case (len)
            3'b000:  sign_extend = {24'b0, mem_din};
            3'b100:  sign_extend = {{24{mem_din[7]}}, mem_din};
            3'b001:  sign_extend = {16'b0, mem_din[7:0], value[7:0]};
            3'b101:  sign_extend = {{16{mem_din[7]}}, mem_din[7:0], value[7:0]};
            3'b010:  sign_extend = {mem_din[7:0], value[23:0]};
            3'b110:  sign_extend = {mem_din[7:0], value[23:0]};
            default: sign_extend = 0;
        endcase
    endfunction
endmodule
