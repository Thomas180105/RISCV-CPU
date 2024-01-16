`include "define.v"

module LoadStoreBuffer #(
    parameter BTIS = `LSB_BITS,
    parameter SIZE = `LSB_SIZE
) (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire need_LSB,
    input wire [6:0] opcode, // <output from decoder>
    input wire [4:0] rd,
    input wire [4:0] rs1,
    input wire [4:0] rs2,
    input wire [2:0] funct3,
    input wire funct7,
    input wire [31:0] imm,
    input wire [31:0] pc,

    // for memory
    input wire [31:0] mem_result,
    input wire mem_rdy,

    // for register
    input wire [`RoB_BITS-1:0] i_rs1_q,
    input wire [`RoB_BITS-1:0] i_rs2_q,
    input wire i_rs1_ready,  
    input wire i_rs2_ready,  
    input wire [31:0] i_rs1_value,
    input wire [31:0] i_rs2_value,

    // for RoB
    input wire RoB_clear,
    input wire issue_ready,
    input wire [`RoB_BITS-1:0] RoB_head,
    input wire [`RoB_BITS-1:0] RoB_tail,
    input wire RoB_rdy_RS,
    input wire [`RoB_BITS-1:0] RoB_id_RS,  
    input wire [31:0] RoB_value_RS,
    input wire RoB_rdy_LSB,
    input wire [`RoB_BITS-1:0] RoB_id_LSB,
    input wire [31:0] RoB_value_LSB,

    output wire [`RoB_BITS-1:0] get_RoB_id_1,  // get value from RoB if q_i is not ready
    output wire [`RoB_BITS-1:0] get_RoB_id_2,
    input wire RoB_busy_1,
    input wire RoB_busy_2,
    input wire [31:0] get_RoB_value_1,
    input wire [31:0] get_RoB_value_2,

    output wire d_waiting, // <input to Cache>
    output wire d_wr,
    output wire [31:0] d_addr,
    output wire [31:0] d_value,
    output wire [2:0] d_len,

    output wire LSB_finish_rdy,
    output wire [`RoB_BITS-1:0] LSB_finish_id,
    output wire [31:0] LSB_finish_value,

    output wire full
);

    wire is_U = opcode == 7'b0110111 || opcode == 7'b0010111;
    wire is_J = opcode == 7'b1101111;
    wire is_I = opcode == 7'b0010011 || opcode == 7'b0000011 || opcode == 7'b1100111;
    wire is_S = opcode == 7'b0100011;
    wire is_B = opcode == 7'b1100011;
    wire is_R = opcode == 7'b0110011;
    wire is_load = opcode == 7'b0000011;
    wire is_jail = opcode == 7'b1100111;

    reg [BTIS-1:0] head;
    reg [BTIS-1:0] tail;


    reg [31:0] vj[SIZE-1:0];
    reg [31:0] vk[SIZE-1:0];
    reg [31:0] qj[SIZE-1:0];
    reg [31:0] qk[SIZE-1:0];
    reg rdj[SIZE-1:0];  
    reg rdk[SIZE-1:0];  
    reg [`RoB_BITS-1:0] dest[SIZE-1:0];  // id in RoB
    reg [31:0] imm_info[SIZE-1:0];
    reg [2:0] op[SIZE-1:0]; // encode (lb, lh, lw, lbu, lhu, sb, sh, sw)

    //             if (!is_S) begin
    //                 case (funct3) // store
    //                     3'b000: op[tail] <= 3'b000; // lb
    //                     3'b001: op[tail] <= 3'b001; // lh
    //                     3'b010: op[tail] <= 3'b010; // lw
    //                     3'b100: op[tail] <= 3'b011; // lbu
    //                     3'b101: op[tail] <= 3'b100; // lhu
    //                 endcase
    //             end
    //             else begin // load
    //                 case (funct3)
    //                     3'b000: op[tail] <= 3'b101; // sb
    //                     3'b001: op[tail] <= 3'b110; // sh
    //                     3'b010: op[tail] <= 3'b111; // sw
    //                 endcase
    //             end

    reg filled[SIZE-1:0];
    assign full = head == tail && filled[head];

    assign d_waiting = filled[head] && rdj[head] && rdk[head] && (op[head] <= 3'd4 || dest[head] == RoB_head);
    assign d_addr = vj[head] + imm_info[head];
    assign d_wr = op[head] > 3'b100;
    assign d_value = vk[head]; // used for store
    assign d_len = op[head] == 3'b000 ? 3'b100 :  
        op[head] == 3'b001 ? 3'b101 :  
        op[head] == 3'b010 ? 3'b110 :  
        op[head] == 3'b011 ? 3'b000 :  
        op[head] == 3'b100 ? 3'b001 :  
        op[head] == 3'b101 ? 3'b100 :  
        op[head] == 3'b110 ? 3'b101 : 3'b110;

    assign get_RoB_id_1 = i_rs1_q;
    assign get_RoB_id_2 = i_rs2_q; 

    assign LSB_finish_rdy = filled[head] && mem_rdy;
    assign LSB_finish_id = dest[head];
    assign LSB_finish_value = mem_result;   

    integer i;

    always @(posedge clk_in) begin
        if (rst_in || RoB_clear) begin
            head <= 0;
            tail <= 0;
            for (i = 0; i < SIZE; i = i + 1) begin
                filled[i] <= 0;
                vj[i] <= 0;
                vk[i] <= 0;
                qj[i] <= 0;
                qk[i] <= 0;
                op[i] <= 0;
                rdj[i] <= 0;
                rdk[i] <= 0;
                imm_info[i] <= 0;
                dest[i] <= 0;
            end
        end
        else if (rdy_in) begin
            if (issue_ready && need_LSB && !filled[tail]) begin
                tail <= tail + 1;
                filled[tail] <= 1;
                dest[tail] <= RoB_tail;
                imm_info[tail] <= opcode == 7'b0010111 ? pc + imm : imm;

                if (i_rs1_ready) begin // 1 if not dependent
                    vj[tail]  <= i_rs1_value;
                    qj[tail]  <= 0;
                    rdj[tail] <= 1;
                end
                else begin
                    if (RoB_rdy_RS && i_rs1_q == RoB_id_RS) begin // get value from latest RSRow
                        vj[tail]  <= RoB_value_RS;
                        qj[tail]  <= 0;
                        rdj[tail] <= 1;
                    end
                    else if (i_rs1_q == RoB_id_LSB && RoB_rdy_LSB) begin // get value from LSBRow
                        vj[tail]  <= RoB_value_LSB;
                        qj[tail]  <= 0;
                        rdj[tail] <= 1;
                    end
                    else if (!RoB_busy_1) begin 
                        vj[tail]  <= get_RoB_value_1;
                        qj[tail]  <= 0;
                        rdj[tail] <= 1;
                    end
                    else begin
                        qj[tail]  <= i_rs1_q;
                        rdj[tail] <= 0;
                    end
                end
                if (is_S) begin
                    if (i_rs2_ready) begin
                        vk[tail]  <= i_rs2_value;
                        qk[tail]  <= 0;
                        rdk[tail] <= 1;
                    end
                    else begin
                        if (RoB_rdy_RS && i_rs2_q == RoB_id_RS) begin
                            vk[tail]  <= RoB_value_RS;
                            qk[tail]  <= 0;
                            rdk[tail] <= 1;
                        end
                        else if (i_rs2_q == RoB_id_LSB && RoB_rdy_LSB) begin
                            vk[tail]  <= RoB_value_LSB;
                            qk[tail]  <= 0;
                            rdk[tail] <= 1;
                        end
                        else if (!RoB_busy_2) begin
                            vk[tail]  <= get_RoB_value_2;
                            qk[tail]  <= 0;
                            rdk[tail] <= 1;
                        end
                        else begin
                            qk[tail]  <= i_rs2_q;
                            rdk[tail] <= 0;
                        end
                    end
                end
                else begin
                    vk[tail]  <= 0;
                    qk[tail]  <= 0;
                    rdk[tail] <= 1;
                end

                if (!is_S) begin
                    case (funct3)
                        3'b000: op[tail] <= 3'b000;
                        3'b001: op[tail] <= 3'b001;
                        3'b010: op[tail] <= 3'b010;
                        3'b100: op[tail] <= 3'b011;
                        3'b101: op[tail] <= 3'b100;
                    endcase
                end
                else begin
                    case (funct3)
                        3'b000: op[tail] <= 3'b101;
                        3'b001: op[tail] <= 3'b110;
                        3'b010: op[tail] <= 3'b111;
                    endcase
                end
            end
            if (mem_rdy) begin
                filled[head] <= 0;
                head <= head + 1;
            end

            for (i = 0; i < SIZE; i = i + 1) begin
                if (filled[i]) begin                                    
                    if (!rdj[i] && qj[i] == RoB_id_RS && RoB_rdy_RS) begin
                        vj[i]  <= RoB_value_RS;
                        qj[i]  <= 0;
                        rdj[i] <= 1;
                    end
                    if (!rdj[i] && qj[i] == RoB_id_LSB && RoB_rdy_LSB) begin
                        vj[i]  <= RoB_value_LSB;
                        qj[i]  <= 0;
                        rdj[i] <= 1;
                    end
                    if (!rdk[i] && qk[i] == RoB_id_RS && RoB_rdy_RS) begin
                        vk[i]  <= RoB_value_RS;
                        qk[i]  <= 0;
                        rdk[i] <= 1;
                    end
                    if (!rdk[i] && qk[i] == RoB_id_LSB && RoB_rdy_LSB) begin
                        vk[i]  <= RoB_value_LSB;
                        qk[i]  <= 0;
                        rdk[i] <= 1;
                    end
                end
            end
        end
    end
endmodule
