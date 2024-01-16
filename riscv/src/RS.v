`include "define.v"

module ReserveStation #(
    parameter BITS = `RS_BITS,
    parameter SIZE = `RS_SIZE
) (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    // decoder
    input wire need_LSB,
    input wire [31:0] pc,
    input wire [4:0] rs1,
    input wire [4:0] rs2,
    input wire [4:0] rd,
    input wire [2:0] funct3,
    input wire funct7,
    input wire [6:0] opcode, // <output from decoder>
    input wire [31:0] imm,

    // register
    input wire [`RoB_BITS-1:0] i_rs1_q,
    input wire [`RoB_BITS-1:0] i_rs2_q,
    input wire i_rs1_ready,  
    input wire i_rs2_ready, 
    input wire [31:0] i_rs1_value,
    input wire [31:0] i_rs2_value,

    // RoB
    input wire RoB_clear,
    input wire issue_ready,
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

    // for ALU
    input wire ALU_finish_rdy,
    output wire waiting_ALU,
    output wire [31:0] vj_ALU,
    output wire [31:0] vk_ALU,
    output wire [5:0] op_ALU,
    output wire [31:0] imm_ALU,


    output wire [`RoB_BITS-1:0] RS_finish_id,
    output wire full
);

    wire is_U = opcode == 7'b0110111 || opcode == 7'b0010111;
    wire is_J = opcode == 7'b1101111;
    wire is_I = opcode == 7'b0010011 || opcode == 7'b0000011 || opcode == 7'b1100111;
    wire is_S = opcode == 7'b0100011;
    wire is_B = opcode == 7'b1100011;
    wire is_R = opcode == 7'b0110011;
    wire is_load = opcode == 7'b0000011;
    wire is_jalr = opcode == 7'b1100111;

    wire need_RS = !need_LSB;
    //vj: reg value, qj: dependency RoB id, rdj: 1 if no dependency
    reg [31:0] vj[SIZE-1:0];
    reg [31:0] vk[SIZE-1:0];
    reg [31:0] qj[SIZE-1:0];
    reg [31:0] qk[SIZE-1:0];
    reg rdj[SIZE-1:0];  
    reg rdk[SIZE-1:0];  
    wire rdjk[SIZE-1:0]; 
    reg [`RoB_BITS-1:0] dest[SIZE-1:0];  // id in RoB
    reg [31:0] imm_info[SIZE-1:0];
    reg [5:0] op[SIZE-1:0];  // func7, func3, 0: U, 1: I, 2: B, 3: R; if 6'b111111, then it is J

    reg filled[SIZE-1:0];   // if the place is not empty
    reg working[SIZE-1:0];  // 1: issued but don't get all the value
    reg waiting[SIZE-1:0];  // 1: waiting for result from ALU
    wire just_finishing[SIZE-1:0]; // 1 : just get result from ALU  
    
    
    wire [BITS-1:0] t_empty[SIZE-1:0]; // tree, t_empty[1] is the first empty place(!filled)
    wire [BITS-1:0] t_rdjk[SIZE-1:0];  // tree, t_rdjk[1] is the first ready place(rdjk && filled)
    wire [BITS-1:0] t_finished[SIZE-1:0];  // t_finished working id

    generate
        genvar ii;        
        for (ii = 0; ii < (1 << BITS); ii = ii + 1) begin : gen0
            assign rdjk[ii] = rdj[ii] && rdk[ii] && filled[ii];
            assign just_finishing[ii] = !working[ii] && !waiting[ii] && filled[ii];
        end
        for (ii = 0; ii < (1 << (BITS - 1)); ii = ii + 1) begin : gen1
            assign t_empty[ii] = !filled[t_empty[ii<<1]] ? t_empty[ii<<1] : t_empty[(ii<<1)|1];

            assign t_rdjk[ii] = rdjk[t_rdjk[ii<<1]] ? t_rdjk[ii<<1] : t_rdjk[(ii<<1)|1];

            assign t_finished[ii] = just_finishing[t_finished[ii<<1]] ? t_finished[ii<<1] : t_finished[(ii<<1)|1];
        end
        for (ii = (1 << (BITS - 1)); ii < (1 << BITS); ii = ii + 1) begin : gen2
            assign t_empty[ii] = !filled[(ii<<1)-SIZE] ? (ii << 1) - SIZE : ((ii << 1) | 1) - SIZE;

            assign t_rdjk[ii] = rdjk[(ii<<1)-SIZE] ? (ii << 1) - SIZE : ((ii << 1) | 1) - SIZE;

            assign t_finished[ii] = just_finishing[(ii<<1)-SIZE] ? (ii << 1) - SIZE : ((ii << 1) | 1) - SIZE;
        end
    endgenerate

    wire [BITS-1:0] cur_id = t_empty[1];
    wire ready = need_RS && !filled[cur_id];
    assign full = filled[cur_id];

    wire [BITS-1:0] rdy_work_id = t_rdjk[1];
    wire [BITS-1:0] finish_id = t_finished[1];

    assign waiting_ALU = rdjk[rdy_work_id] && filled[rdy_work_id] && working[rdy_work_id];
    assign vj_ALU = vj[rdy_work_id];
    assign vk_ALU = vk[rdy_work_id];
    assign imm_ALU = imm_info[rdy_work_id];
    assign op_ALU = op[rdy_work_id];

    assign get_RoB_id_1 = i_rs1_q;
    assign get_RoB_id_2 = i_rs2_q;

    assign RS_finish_id = dest[rdy_work_id];

    integer i;

    always @(posedge clk_in) begin
        if (rst_in || RoB_clear) begin
            for (i = 0; i < SIZE; i = i + 1) begin
                filled[i]    <= 0;
                working[i] <= 0;
                waiting[i] <= 0;
                vj[i]      <= 0;
                vk[i]      <= 0;
                qj[i]      <= 0;
                qk[i]      <= 0;
                rdj[i]     <= 0;
                rdk[i]     <= 0;
                imm_info[i]       <= 0;
                dest[i]    <= 0;
                op[i]      <= 0;
            end            
        end
        else if (rdy_in) begin
            if (issue_ready && ready) begin
                filled[cur_id] <= 1;
                working[cur_id] <= 1;
                dest[cur_id] <= RoB_tail;
                imm_info[cur_id] <= opcode == 7'b0010111 ? pc + imm : imm;

                if (!(is_U || is_J)) begin                
                    if (i_rs1_ready) begin   // 1 if not dependent                              
                        vj[cur_id]  <= i_rs1_value;
                        qj[cur_id]  <= 0;
                        rdj[cur_id] <= 1;
                    end
                    else begin
                        if (RoB_rdy_RS && (i_rs1_q == RoB_id_RS)) begin // get value from latest RSRow
                            vj[cur_id]  <= RoB_value_RS;
                            qj[cur_id]  <= 0;
                            rdj[cur_id] <= 1;
                        end
                        else if (RoB_rdy_LSB && (i_rs1_q == RoB_id_LSB)) begin // get value from LSBRow
                            vj[cur_id]  <= RoB_value_LSB;
                            qj[cur_id]  <= 0;
                            rdj[cur_id] <= 1;
                        end
                        else if (!RoB_busy_1) begin 
                            vj[cur_id]  <= get_RoB_value_1;
                            qj[cur_id]  <= 0;
                            rdj[cur_id] <= 1;
                        end
                        else begin
                            vj[cur_id]  <= 0;
                            qj[cur_id]  <= i_rs1_q;
                            rdj[cur_id] <= 0;
                        end
                    end
                end
                else begin
                    vj[cur_id]  <= 0;
                    qj[cur_id]  <= 0;
                    rdj[cur_id] <= 1;
                end

                if (is_J) begin
                    op[cur_id] <= 6'b111111;
                end
                else begin
                    if (is_U) op[cur_id] <= {funct7, funct3, 2'd0};
                    else if (is_I) op[cur_id] <= {funct7, funct3, 2'd1};
                    else if (is_B) op[cur_id] <= {funct7, funct3, 2'd2};
                    else if (is_R) op[cur_id] <= {funct7, funct3, 2'd3};
                end

                if (is_B || is_S || is_R) begin
                    if (i_rs2_ready) begin
                        vk[cur_id]  <= i_rs2_value;
                        qk[cur_id]  <= 0;
                        rdk[cur_id] <= 1;
                    end
                    else begin
                        if (RoB_rdy_RS && (i_rs2_q == RoB_id_RS)) begin
                            vk[cur_id]  <= RoB_value_RS;
                            qk[cur_id]  <= 0;
                            rdk[cur_id] <= 1;
                        end
                        else if (RoB_rdy_LSB && (i_rs2_q == RoB_id_LSB)) begin
                            vk[cur_id]  <= RoB_value_LSB;
                            qk[cur_id]  <= 0;
                            rdk[cur_id] <= 1;
                        end
                        else if (!RoB_busy_2) begin
                            vk[cur_id]  <= get_RoB_value_2;
                            qk[cur_id]  <= 0;
                            rdk[cur_id] <= 1;
                        end
                        else begin
                            vk[cur_id]  <= 0;
                            qk[cur_id]  <= rs2;
                            rdk[cur_id] <= 0;
                        end
                    end
                end
                else begin
                    vk[cur_id]  <= 0;
                    qk[cur_id]  <= 0;
                    rdk[cur_id] <= 1;
                end
            end

            if (rdj[rdy_work_id] && rdk[rdy_work_id] && filled[rdy_work_id]) begin
                if (working[rdy_work_id]) begin
                    working[rdy_work_id] <= 0;
                    waiting[rdy_work_id] <= 1;
                end
                else if (waiting[rdy_work_id] && ALU_finish_rdy) begin
                    waiting[rdy_work_id] <= 0;
                    filled[rdy_work_id] <= 0;
                end
            end

            for (i = 0; i < SIZE; i = i + 1) begin
                if (filled[i] && working[i]) begin                                    
                    if (!rdj[i] && qj[i] == RoB_id_RS && RoB_rdy_RS) begin // get value from RS
                        vj[i]  <= RoB_value_RS;
                        qj[i]  <= 0;
                        rdj[i] <= 1;
                    end
                    if (!rdj[i] && qj[i] == RoB_id_LSB && RoB_rdy_LSB) begin // get value from LSB
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
