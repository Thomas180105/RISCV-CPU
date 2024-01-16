module Decoder (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire RS_full,  
    input wire LSB_full,  
    input wire RoB_full,  
    input wire RoB_stall, 
    output wire need_LSB,
    output wire stall,
    input wire fetch_ready,
    output wire issue_ready,

    input wire [31:0] inst,
    input wire [31:0] pc,

    output wire [6:0] opcode,
    output wire [4:0] rs1,
    output wire [4:0] rs2,
    output wire [4:0] rd,
    output wire [2:0] funct3,
    output wire funct7,
    output wire [31:0] imm,

    input wire pred_res, // 1 if decide to jump( pc = pc + imm), 0 if pc = pc + 4
    output wire pc_change_flag,
    output wire [31:0] pc_change_value,
    output wire [31:0] pc_unselected_value //Unselected pc values at conditional jumps
);

    assign opcode = inst[6:0];
    assign rd = inst[11:7];
    assign funct3 = inst[14:12];
    assign rs1 = inst[19:15];
    assign rs2 = inst[24:20];
    assign funct7 = inst[30];

    assign is_R = (opcode == 7'b0110011);
    assign is_I = (opcode == 7'b0010011) || (opcode == 7'b0000011) || (opcode == 7'b1100111);
    assign is_S = (opcode == 7'b0100011);
    assign is_B = (opcode == 7'b1100011);
    assign is_U = (opcode == 7'b0110111) || (opcode == 7'b0010111);
    assign is_J = (opcode == 7'b1101111);

    assign is_load = opcode == 7'b0000011;
    assign is_jalr = opcode == 7'b1100111;

    assign need_LSB = is_S || opcode == 7'b0000011; // store or load

    wire [11:0] imm_I = inst[31:20];
    wire [11:0] imm_S = {inst[31:25], inst[11:7]};
    wire [12:0] imm_B = {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
    wire [19:0] imm_U = inst[31:12];
    wire [20:0] imm_J = {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};

    assign imm = is_U ? {imm_U, 12'b0} :  
        is_J ? {{11{imm_J[20]}}, imm_J} :  
        is_B ? {{19{imm_B[12]}}, imm_B} : 
        is_S ? {{20{imm_S[11]}}, imm_S} : 
        (opcode == 7'b0010011 && funct3 == 3'b001 || funct3 == 3'b101) ? {27'b0, rs2} : {{20{imm_I[11]}}, imm_I};  

    assign stall = RoB_full || RoB_stall || (need_LSB && LSB_full) || (!need_LSB && RS_full);

    assign issue_ready = !stall && fetch_ready;

    assign pc_change_flag = (is_J || (is_B && pred_res)) && issue_ready; //Attention: issue_ready needed here!
    assign pc_change_value = pc + imm;
    assign pc_unselected_value = pred_res ? pc + 4 : pc + imm;

    // always @(posedge clk_in) begin
    //     if (rst_in) begin

    //     end
    //     else if (rdy_in) begin
    //             $display("here: %h, %d %h", inst, pc, pc);
    //         if (fetch_ready && issue_ready) begin
    //              $display("inst: %h, %d %h", inst, pc, pc);
    //         end
    //     end
    // end

endmodule
