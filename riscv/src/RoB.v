`include "define.v"

module ReorderBuffer #(
    parameter BITS = `RoB_BITS,
    parameter Size = `RoB_SIZE
) (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire issue_ready,
    input wire [31:0] inst,
    input wire [31:0] pc,
    input wire [31:0] pc_unselected_value,  // what pc should be if branch fails

    input wire [6:0] opcode,
    input wire [4:0] rd,

    input wire [BITS-1:0] get_RoB_id_1,  // get value from RoB if q is not ready
    input wire [BITS-1:0] get_RoB_id_2,
    output wire RoB_busy_1,              // busy[]: 1 if still not get result, otherwise 0
    output wire RoB_busy_2,
    output wire [31:0] get_RoB_value_1,
    output wire [31:0] get_RoB_value_2,

    // RS and RoB
    input wire RS_finish_rdy,
    input wire [BITS-1:0] RS_finish_id,
    input wire [31:0] RS_finish_value,
    output wire RoB_rdy_RS,            // eq to RS_finish_rdy
    output wire [BITS-1:0] RoB_id_RS,  // eq to RS_finish_id
    output wire [31:0] RoB_value_RS,    // eq to RS_finish_value

    // LSB and RoB
    input wire LSB_finish_rdy,
    input wire [BITS-1:0] LSB_finish_id,
    input wire [31:0] LSB_finish_value,
    output wire RoB_rdy_LSB,
    output wire [BITS-1:0] RoB_id_LSB,
    output wire [31:0] RoB_value_LSB,

    output wire [BITS-1:0] RoB_head,
    output wire [BITS-1:0] RoB_tail,
    output wire full,
    output reg stall,
    output wire RoB_clear,
    output wire [31:0] RoB_clear_pc_value,

    output wire [ 4:0] set_reg_id,    // RoB execution
    output wire [31:0] set_reg_value, 

    output wire [ 4:0] set_reg_q_1,  // when issue
    output wire [31:0] set_val_q_1,  // i.e. tail
    output wire [ 4:0] set_reg_q_2,  // when commit
    output wire [31:0] set_val_q_2  // i.e. head
);

    wire is_J = opcode == 7'b1101111;
    wire is_B = opcode == 7'b1100011;
    wire is_S = opcode == 7'b0100011;
    wire is_jalr = opcode == 7'b1100111;

    reg [BITS-1:0] head;
    reg [BITS-1:0] tail;
    reg busy[Size-1:0];           // 1 if still not get result, otherwise 0
    reg free[Size-1:0];           // empty
    reg [31:0] value[Size-1:0];   // res of calc/mem are stored, except for branch/jal/jalr,s pc related value are stored
    reg [31:0] dest[Size-1:0];    // if not branch dest = rd, else dest = pc_unselected_value
    reg [1:0] op[Size-1:0];       // 0: write register(except jalr), 1: store, 2: branch, 3: jalr
    reg [31:0] pc_jalr[Size-1:0]; // what pc value should be under jalr

    assign RoB_head = head;
    assign RoB_tail = tail;
    assign full = head == tail && !free[head];

    assign RoB_id_RS = RS_finish_id;
    assign RoB_id_LSB = LSB_finish_id;
    assign RoB_rdy_RS = RS_finish_rdy;
    assign RoB_rdy_LSB = LSB_finish_rdy;
    assign RoB_value_RS = RS_finish_value;
    assign RoB_value_LSB = LSB_finish_value;

    assign RoB_busy_1 = busy[get_RoB_id_1];
    assign RoB_busy_2 = busy[get_RoB_id_2];
    assign get_RoB_value_1 = value[get_RoB_id_1];
    assign get_RoB_value_2 = value[get_RoB_id_2];

    wire head_ready = !free[head] && !busy[head];

    assign set_reg_id = (head_ready && (op[head] == 2'd0 || op[head] == 2'd3)) ? dest[head] : 0; //  i.e. when write register, get the register id
    assign set_reg_value = value[head];

    assign set_reg_q_1 = (issue_ready && !(is_B || is_S)) ? rd : 0;
    assign set_val_q_1 = tail;
    assign set_reg_q_2 = (head_ready && !op[head]) ? dest[head] : 0;
    assign set_val_q_2 = head;

    // ready to work on head, but it's jalr or branch that actually take +imm(since all branch we decide to +4)
    assign RoB_clear = head_ready && (op[head] == 2'd3 || (op[head] == 2'd2 && (value[head] & 32'd1))); 
    assign RoB_clear_pc_value = (op[head] == 2'd2)? (dest[head]) : pc_jalr[head];    

    integer i;

    always @(posedge clk_in) begin
        if (rst_in || RoB_clear) begin
            head  <= 0;
            tail  <= 0;
            stall <= 0;
            for (i = 0; i < Size; i = i + 1) begin
                busy[i]  <= 0;
                free[i]  <= 1;
                value[i] <= 0;
                dest[i]  <= 0;
                op[i]    <= 0;
                pc_jalr[i] <= 0;
            end
        end
        else if (rdy_in) begin
            if (issue_ready) begin
                
                tail <= tail + 1;
                busy[tail] <= 1;
                free[tail] <= 0;   

                if (is_S) begin
                    op[tail] <= 2'd1;
                end
                else if (is_B) begin
                    op[tail] <= 2'd2;
                end
                else if (is_jalr) begin
                    op[tail] <= 2'd3;
                end
                else begin
                    op[tail] <= 2'd0;
                end  

                //deal with branch and jal jalr, save the pc value to value[]           
                if (is_B) begin
                    value[tail] <= pc;
                end
                else if (is_jalr) begin
                    value[tail] <= pc + 4;                    
                    stall <= 1;
                end
                else if (is_J) begin
                    value[tail] <= pc + 4;
                end
                else begin
                    value[tail] <= 0;
                end

                if (is_B) begin
                    dest[tail] <= pc_unselected_value; // i.e. pc + imm
                end
                else if (!is_S) begin
                    dest[tail] <= rd;
                end
            end

            if (LSB_finish_rdy) begin
                busy[LSB_finish_id]  <= 0;
                value[LSB_finish_id] <= LSB_finish_value;
            end
            if (RS_finish_rdy) begin
                busy[RS_finish_id] <= 0;
                if (op[RS_finish_id] == 2'd2) begin // branch
                    value[RS_finish_id] <= RS_finish_value ^ value[RS_finish_id];
                end
                else if (op[RS_finish_id] == 2'd3) begin // jalr
                    pc_jalr[RS_finish_id] <= RS_finish_value;
                end
                else if (!value[RS_finish_id]) begin
                    value[RS_finish_id] <= RS_finish_value;
                end
            end

            if (!busy[head] && !free[head]) begin
                free[head] <= 1;
                head <= head + 1;
                case (op[head])
                    2'd3: begin
                        stall <= 0;
                    end
                endcase
            end
        end
    end

endmodule
