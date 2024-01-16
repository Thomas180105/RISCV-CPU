module ALU (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire RoB_clear,
    input wire rdy_in,  // ready signal, pause cpu when low

    input wire [31:0] vj,
    input wire [31:0] vk,
    input wire [31:0] imm,
    input wire [5:0]  op,
    input wire waiting,

    output wire finish,
    output wire [31:0] ALU_value
);

reg ready;
reg [31:0] value;

assign finish = ready;
assign ALU_value = value;

always @(posedge clk_in) begin
    if (rst_in || RoB_clear) begin
        ready <= 0;
        value <= 0;
    end
    else if (rdy_in) begin
        if (!waiting) begin  // not waiting
            ready <= 0;
            value <= 0;
        end
        else begin           // waiting
            ready <= 1;
            if (op == 6'b111111) begin
                value <= 0;
            end
            else begin
                case (op[1:0])
                    2'b00: begin // U
                        value <= imm;
                    end
                    2'b01: begin // I
                        case (op[4:2])
                            3'b000: begin // addi
                                value <= vj + imm;
                            end
                            3'b010: begin // slti
                                value <= ($signed(vj) < $signed(imm)) ? 1 : 0;
                            end
                            3'b011: begin // sltiu
                                value <= ($unsigned(vj) < $unsigned(imm)) ? 1 : 0;
                            end
                            3'b100: begin // xori
                                value <= vj ^ imm;
                            end
                            3'b110: begin // ori
                                value <= vj | imm;
                            end
                            3'b111: begin // andi
                                value <= vj & imm;
                            end
                            3'b001: begin // slli
                                value <= vj << imm[4:0];
                            end
                            3'b101: begin 
                                if (op[5]) begin
                                    value <= vj >>> imm[4:0]; // srai 
                                end
                                else begin
                                    value <= vj >> imm[4:0]; // srli
                                end
                            end
                        endcase
                    end
                    2'b10: begin // B
                        case (op[4:2])
                            3'b000: begin // beq
                                value <= (vj == vk) ? 1 : 0;
                            end
                            3'b001: begin // bne
                                value <= (vj != vk) ? 1 : 0;
                            end
                            3'b100: begin // blt
                                value <= ($signed(vj) < $signed(vk)) ? 1 : 0;
                            end
                            3'b101: begin // bge
                                value <= ($signed(vj) >= $signed(vk)) ? 1 : 0;
                            end
                            3'b110: begin // bltu
                                value <= ($unsigned(vj) < $unsigned(vk)) ? 1 : 0;
                            end
                            3'b111: begin // bgeu
                                value <= ($unsigned(vj) >= $unsigned(vk)) ? 1 : 0;
                            end
                        endcase
                    end
                    2'b11: begin // R
                        case (op[4:2])
                            3'b000: begin
                                if (op[5]) begin
                                    value <= vj - vk; // sub
                                end
                                else begin
                                    value <= vj + vk; // add
                                end
                            end
                            3'b001: begin // sll
                                value <= vj << (vk[4:0]);
                            end
                            3'b010: begin // slt
                                value <= ($signed(vj) < $signed(vk)) ? 1 : 0;
                            end
                            3'b011: begin // sltu
                                value <= ($unsigned(vj) < $unsigned(vk)) ? 1 : 0;
                            end
                            3'b100: begin // xor
                                value <= vj ^ vk;
                            end
                            3'b101: begin // srl, sra
                                if (op[5]) begin
                                    value <= vj >>> (vk[4:0] & 5'h1f); // sra
                                end
                                else begin
                                    value <= vj >> (vk[4:0] & 5'h1f); // srl
                                end
                            end
                            3'b110: begin // or
                                value <= vj | vk;
                            end
                            3'b111: begin // and
                                value <= vj & vk;
                            end
                        endcase
                    end
                endcase
            end
        end
        
    end
end

endmodule
