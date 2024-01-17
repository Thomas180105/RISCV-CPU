// RISCV32I CPU top module
// port modification allowed for debugging purposes
`include "define.v"

module cpu(
  input  wire                 clk_in,			// system clock signal
  input  wire                 rst_in,			// reset signal
	input  wire					        rdy_in,			// ready signal, pause cpu when low

  input  wire [ 7:0]          mem_din,		// data input bus
  output wire [ 7:0]          mem_dout,		// data output bus
  output wire [31:0]          mem_a,			// address bus (only 17:0 is used)
  output wire                 mem_wr,			// write/read signal (1 for write)
	
	input  wire                 io_buffer_full, // 1 if uart buffer is full
	
	output wire [31:0]			dbgreg_dout		// cpu register output (debugging demo)
);

// implementation goes here

// Specifications:
// - Pause cpu(freeze pc, registers, etc.) when rdy_in is low
// - Memory read result will be returned in the next cycle. Write takes 1 cycle(no need to wait)
// - Memory is of size 128KB, with valid address ranging from 0x0 to 0x20000
// - I/O port is mapped to address higher than 0x30000 (mem_a[17:16]==2'b11)
// - 0x30000 read: read a byte from input
// - 0x30000 write: write a byte to output (write 0x00 is ignored)
// - 0x30004 read: read clocks passed since cpu starts (in dword, 4 bytes)
// - 0x30004 write: indicates program stop (will output '\0' through uart tx)

// always @(posedge clk_in)
//   begin
//     if (rst_in)
//       begin
      
//       end
//     else if (!rdy_in)
//       begin
      
//       end
//     else
//       begin
      
//       end
//   end


// wire strict_rdy_in = rdy_in && !io_buffer_full;
wire strict_rdy_in = rdy_in;
wire i_ready;
wire fetch_ready;
wire [31:0] inst;
wire [31:0] i_result;
wire [31:0] pc;
wire d_wr;
wire d_waiting;
wire [31:0] d_addr;
wire [31:0] d_value;
wire [2:0] d_len;
wire [31:0] d_result;
wire d_ready;
wire RoB_clear;
wire decoder_pc_change_flag;
wire pc_change_flag = RoB_clear | decoder_pc_change_flag;
wire [31:0] decoder_pc_change_value;
wire [31:0] RoB_clear_pc_value;
wire [31:0] pc_change_value = RoB_clear ? RoB_clear_pc_value : decoder_pc_change_value;
wire i_fetch_stall;
wire RS_full;
wire LSB_full;
wire RoB_full;
wire RoB_stall;

wire [6:0] opcode;
wire [4:0] rd;
wire [4:0] rs1;
wire [4:0] rs2;
wire [2:0] funct3;
wire funct7;
wire [31:0] imm;
wire need_LSB;
wire issue_ready;
wire [31:0] pc_unselected_value;
wire [`RoB_BITS-1:0] i_rs1_q;
wire [`RoB_BITS-1:0] i_rs2_q;
wire i_rs1_ready;
wire i_rs2_ready; 
wire [31:0] i_rs1_value;
wire [31:0] i_rs2_value;
wire [ 4:0] set_reg;
wire [31:0] set_val;
wire [ 4:0] set_q_index_1;  
wire [31:0] set_q_val_1;    // (only [3:0] used)   
wire [ 4:0] set_q_index_2;  
wire [31:0] set_q_val_2;    // (only [3:0] used)  

wire [`RoB_BITS-1:0] RS_finish_id;
wire LSB_finish_rdy;
wire [`RoB_BITS-1:0] LSB_finish_id;
wire [31:0] LSB_finish_value;
wire [3:0] RoB_head;
wire [3:0] RoB_tail;

wire RoB_rdy_RS;            // eq to RS_finish_rdy
wire [`RoB_BITS-1:0] RoB_id_RS;  // eq to RS_finish_id
wire [31:0] RoB_value_RS;    // eq to RS_finish_value
wire RoB_rdy_LSB;
wire [`RoB_BITS-1:0] RoB_id_LSB;
wire [31:0] RoB_value_LSB;

wire [3:0] get_RoB_id_1;
wire [3:0] get_RoB_id_2;
wire RoB_busy_1;
wire RoB_busy_2;
wire [31:0] get_RoB_value_1;
wire [31:0] get_RoB_value_2;

wire ALU_finish_rdy;
wire waiting_ALU;
wire [31:0] vj_ALU;
wire [31:0] vk_ALU;
wire [31:0] imm_ALU;
wire [5:0] op_ALU;
wire [31:0] ALU_value;

// module Cache (
//     input wire clk_in,  // system clock signal
//     input wire rst_in,  // reset signal
//     input wire RoB_clear,
//     input wire rdy_in,  // ready signal, pause cpu when low

//     input  wire [ 7:0] mem_din,   // data input bus
//     output wire [ 7:0] mem_dout,  // data output bus
//     output wire [31:0] mem_a,     // address bus (only 17:0 is used)
//     output wire        mem_wr,    // write/read signal (1 for write)

//     //instruction cache
//     input wire i_waiting,  
//     input wire [31:0] i_addr, 

//     output wire [31:0] i_result,  // result of read 
//     output wire i_ready,          // ready to return instruction result and accept new read request
    
//     //data cache
//     input wire d_waiting,     
//     input wire [31:0] d_addr,  
//     input wire [31:0] d_value, // value to be written
//     input wire [2:0] d_len,    // length of data to be read/written
//     input wire d_wr,           // write/read signal (1 for write)
//     output wire [31:0] d_result, 
//     output wire d_ready
// );

Cache cache (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .RoB_clear(RoB_clear),
    .rdy_in(strict_rdy_in),

    .mem_din(mem_din),
    .mem_dout(mem_dout),
    .mem_a(mem_a),
    .mem_wr(mem_wr),

    .i_waiting(1'b1),
    .i_addr(pc),

    .i_result(i_result),
    .i_ready(i_ready),

    .d_waiting(d_waiting),
    .d_addr(d_addr),
    .d_value(d_value),
    .d_len(d_len),
    .d_wr(d_wr),
    .d_result(d_result),
    .d_ready(d_ready)
);

// module InstructionFetch (
//     input wire clk_in,  // system clock signal
//     input wire rst_in,  // reset signal
//     input wire RoB_clear,
//     input wire rdy_in,  // ready signal, pause cpu when low

//     input wire pc_change_flag, 
//     input wire [31:0] pc_change_value, 

//     input wire stall,  
//     input wire ready_in,
//     input wire [31:0] inst_in,  

//     input wire [31:0] RoB_clear_pc_value,

//     output wire ready_out,  
//     output wire [31:0] inst_out,  
//     output wire [31:0] pc_out,  // program counter
//     output reg [31:0] addr  
// );

InstructionFetch ifetcher (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .RoB_clear(RoB_clear),
    .rdy_in(strict_rdy_in),

    .pc_change_flag(pc_change_flag),
    .pc_change_value(pc_change_value),

    .stall(i_fetch_stall),
    .ready_in(i_ready),
    .inst_in(i_result),

    .RoB_clear_pc_value(RoB_clear_pc_value),

    .ready_out(fetch_ready),
    .inst_out(inst),
    .pc_out(pc)
    // .addr(addr)
);

// module Decoder (
//     input wire clk_in,  // system clock signal
//     input wire rst_in,  // reset signal
//     input wire rdy_in,  // ready signal, pause cpu when low

//     input wire RS_full,  
//     input wire LSB_full,  
//     input wire RoB_full,  
//     input wire RoB_stall, 
//     output wire need_LSB,
//     output wire stall,
//     input wire fetch_ready,
//     output wire issue_ready,

//     input wire [31:0] inst,
//     input wire [31:0] pc,

//     output wire [6:0] opcode,
//     output wire [4:0] rs1,
//     output wire [4:0] rs2,
//     output wire [4:0] rd,
//     output wire [2:0] funct3,
//     output wire funct7,
//     output wire [31:0] imm,

//     input wire pred_res, // 1 if decide to jump( pc = pc + imm), 0 if pc = pc + 4
//     output wire pc_change_flag,
//     output wire [31:0] pc_change_value
//     output wire [31:0] pc_unselected_value, //Unselected pc values at conditional jumps
// );

Decoder decoder (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .rdy_in(rdy_in),

    .RS_full(RS_full),
    .LSB_full(LSB_full),
    .RoB_full(RoB_full),
    .RoB_stall(RoB_stall),
    .need_LSB(need_LSB),
    .stall(i_fetch_stall),
    .fetch_ready(fetch_ready),
    .issue_ready(issue_ready),

    .inst(inst),
    .pc(pc),

    .opcode(opcode),
    .rs1(rs1),
    .rs2(rs2),
    .rd(rd),
    .funct3(funct3),
    .funct7(funct7),
    .imm(imm),

    .pred_res(1'b0),
    .pc_change_flag(decoder_pc_change_flag),
    .pc_change_value(decoder_pc_change_value),
    .pc_unselected_value(pc_unselected_value)
);

// module Register (
//     input wire clk_in,  // system clock signal
//     input wire rst_in,  // reset signa
//     input wire RoB_clear,
//     input wire rdy_in,  // ready signal, pause cpu when low

    

//     input wire [ 4:0] set_reg,  
//     input wire [31:0] set_val,    

//     input wire [ 4:0] set_q_index_1,  // q index to be set from issue
//     input wire [31:0] set_q_val_1,    // (only [3:0] used)   
//     input wire [ 4:0] set_q_index_2,  // q index to be set from commit
//     input wire [31:0] set_q_val_2,    // (only [3:0] used)  

//     input wire [4:0] get_reg_1,  
//     input wire [4:0] get_reg_2,  
//     output wire [31:0] get_val_1,  
//     output wire [31:0] get_val_2,  
//     output wire [3:0] get_q_value_1,  // q_i value1
//     output wire [3:0] get_q_value_2,  // q_i value2
//     output wire       get_q_ready_1,  // q_i ready1
//     output wire       get_q_ready_2   // q_i ready2
// );

Register register (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .RoB_clear(RoB_clear),
    .rdy_in(rdy_in),

    .set_reg(set_reg),
    .set_val(set_val),

    .set_q_index_1(set_q_index_1),
    .set_q_val_1(set_q_val_1),
    .set_q_index_2(set_q_index_2),
    .set_q_val_2(set_q_val_2),

    .get_reg_1(rs1),
    .get_reg_2(rs2),
    .get_val_1(i_rs1_value),
    .get_val_2(i_rs2_value),
    .get_q_value_1(i_rs1_q),
    .get_q_value_2(i_rs2_q),
    .get_q_ready_1(i_rs1_ready),
    .get_q_ready_2(i_rs2_ready)
);

// module ReorderBuffer #(
//     parameter BITS = `RoB_BITS,
//     parameter Size = `RoB_SIZE
// ) (
//     input wire clk_in,  // system clock signal
//     input wire rst_in,  // reset signal
//     input wire rdy_in,  // ready signal, pause cpu when low

//     input wire issue_ready,
//     input wire [31:0] inst,
//     input wire [31:0] pc,
//     input wire [31:0] pc_unselected_value,  // what pc should be if branch fails

//     input wire [6:0] opcode,
//     input wire [4:0] rd,

//     input wire [BITS-1:0] get_RoB_id_1,  // get value from RoB if q is not ready
//     input wire [BITS-1:0] get_RoB_id_2,
//     output wire RoB_busy_1,              // busy[]: 1 if still not get result, otherwise 0
//     output wire RoB_busy_2,
//     output wire [31:0] get_RoB_value_1,
//     output wire [31:0] get_RoB_value_2,

//     // RS and RoB
//     input wire RS_finish_rdy,
//     input wire [BITS-1:0] RS_finish_id,
//     input wire [31:0] RS_finish_value,
//     output wire RoB_rdy_RS,            // eq to RS_finish_rdy
//     output wire [BITS-1:0] RoB_id_RS,  // eq to RS_finish_id
//     output wire [31:0] RoB_value_RS,    // eq to RS_finish_value

//     // LSB and RoB
//     input wire LSB_finish_rdy,
//     input wire [BITS-1:0] LSB_finish_id,
//     input wire [31:0] LSB_finish_value,
//     output wire RoB_rdy_LSB,
//     output wire [BITS-1:0] RoB_id_LSB,
//     output wire [31:0] RoB_value_LSB,

//     output wire [BITS-1:0] RoB_head,
//     output wire [BITS-1:0] RoB_tail,
//     output wire full,
//     output reg stall,
//     output wire RoB_clear,
//     output wire [31:0] RoB_clear_pc_value,

//     output wire [ 4:0] set_reg_id,
//     output wire [31:0] set_reg_value,

//     output wire [ 4:0] set_reg_q_1,  // when issue
//     output wire [31:0] set_val_q_1,  // i.e. tail
//     output wire [ 4:0] set_reg_q_2,  // when commit
//     output wire [31:0] set_val_q_2  // i.e. head
// );

ReorderBuffer RoB (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .rdy_in(rdy_in),

    .issue_ready(issue_ready),
    .inst(inst),
    .pc(pc),
    .pc_unselected_value(pc_unselected_value),

    .opcode(opcode),
    .rd(rd),

    .get_RoB_id_1(get_RoB_id_1),
    .get_RoB_id_2(get_RoB_id_2),
    .RoB_busy_1(RoB_busy_1),
    .RoB_busy_2(RoB_busy_2),
    .get_RoB_value_1(get_RoB_value_1),
    .get_RoB_value_2(get_RoB_value_2),

    .RS_finish_rdy(ALU_finish_rdy),
    .RS_finish_id(RS_finish_id),
    .RS_finish_value(ALU_value),
    .RoB_rdy_RS(RoB_rdy_RS),
    .RoB_id_RS(RoB_id_RS),
    .RoB_value_RS(RoB_value_RS),

    .LSB_finish_rdy(LSB_finish_rdy),
    .LSB_finish_id(LSB_finish_id),
    .LSB_finish_value(LSB_finish_value),
    .RoB_rdy_LSB(RoB_rdy_LSB),
    .RoB_id_LSB(RoB_id_LSB),
    .RoB_value_LSB(RoB_value_LSB),

    .RoB_head(RoB_head),
    .RoB_tail(RoB_tail),
    .full(RoB_full),
    .stall(RoB_stall),
    .RoB_clear(RoB_clear),
    .RoB_clear_pc_value(RoB_clear_pc_value),

    .set_reg_id(set_reg),
    .set_reg_value(set_val),

    .set_reg_q_1(set_q_index_1),
    .set_val_q_1(set_q_val_1),
    .set_reg_q_2(set_q_index_2),
    .set_val_q_2(set_q_val_2)
);

// module ReserveStation #(
//     parameter BITS = `RS_BITS,
//     parameter SIZE = `RS_SIZE
// ) (
//     input wire clk_in,  // system clock signal
//     input wire rst_in,  // reset signal
//     input wire rdy_in,  // ready signal, pause cpu when low

//     // decoder
//     input wire need_LSB,
//     input wire [31:0] pc,
//     input wire [4:0] rs1,
//     input wire [4:0] rs2,
//     input wire [4:0] rd,
//     input wire [2:0] funct3,
//     input wire funct7,
//     input wire [6:0] opcode,
//     input wire [31:0] imm,

//     // register
//     input wire [`RoB_BITS-1:0] i_rs1_q,
//     input wire [`RoB_BITS-1:0] i_rs2_q,
//     input wire i_rs1_ready,  
//     input wire i_rs2_ready, 
//     input wire [31:0] i_rs1_value,
//     input wire [31:0] i_rs2_value,

//     // RoB
//     input wire RoB_clear,
//     input wire issue_ready,
//     input wire [`RoB_BITS-1:0] RoB_tail,
//     input wire RoB_rdy_RS,
//     input wire [`RoB_BITS-1:0] RoB_id_RS, 
//     input wire [31:0] RoB_value_RS,
//     input wire RoB_rdy_LSB,
//     input wire [`RoB_BITS-1:0] RoB_id_LSB,
//     input wire [31:0] RoB_value_LSB,

//     output wire [`RoB_BITS-1:0] get_RoB_id_1,  // get value from RoB if q_i is not ready
//     output wire [`RoB_BITS-1:0] get_RoB_id_2,
//     input wire RoB_busy_1,
//     input wire RoB_busy_2,
//     input wire [31:0] get_RoB_value_1,
//     input wire [31:0] get_RoB_value_2,

//     // for ALU
//     input wire ALU_finish_rdy,
//     output wire waiting_ALU,
//     output wire [31:0] vj_ALU,
//     output wire [31:0] vk_ALU,
//     output wire [5:0] op_ALU,
//     output wire [31:0] imm_ALU,


//     output wire [`RoB_BITS-1:0] RS_finish_id,
//     output wire full
// );

ReserveStation RS (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .rdy_in(rdy_in),

    .need_LSB(need_LSB),
    .pc(pc),
    .rs1(rs1),
    .rs2(rs2),
    .rd(rd),
    .funct3(funct3),
    .funct7(funct7),
    .opcode(opcode),
    .imm(imm),

    .i_rs1_q(i_rs1_q),
    .i_rs2_q(i_rs2_q),
    .i_rs1_ready(i_rs1_ready),
    .i_rs2_ready(i_rs2_ready),
    .i_rs1_value(i_rs1_value),
    .i_rs2_value(i_rs2_value),

    .RoB_clear(RoB_clear),
    .issue_ready(issue_ready),
    .RoB_tail(RoB_tail),
    .RoB_rdy_RS(RoB_rdy_RS),
    .RoB_id_RS(RoB_id_RS),
    .RoB_value_RS(RoB_value_RS),
    .RoB_rdy_LSB(RoB_rdy_LSB),
    .RoB_id_LSB(RoB_id_LSB),
    .RoB_value_LSB(RoB_value_LSB),

    .get_RoB_id_1(get_RoB_id_1),
    .get_RoB_id_2(get_RoB_id_2),
    .RoB_busy_1(RoB_busy_1),
    .RoB_busy_2(RoB_busy_2),
    .get_RoB_value_1(get_RoB_value_1),
    .get_RoB_value_2(get_RoB_value_2),

    .ALU_finish_rdy(ALU_finish_rdy),
    .waiting_ALU(waiting_ALU),
    .vj_ALU(vj_ALU),
    .vk_ALU(vk_ALU),
    .op_ALU(op_ALU),
    .imm_ALU(imm_ALU),

    .RS_finish_id(RS_finish_id),
    .full(RS_full)
);

// module ALU (
//     input wire clk_in,  // system clock signal
//     input wire rst_in,  // reset signal
//     input wire RoB_clear,
//     input wire rdy_in,  // ready signal, pause cpu when low

//     input wire [31:0] vj,
//     input wire [31:0] vk,
//     input wire [31:0] imm,
//     input wire [5:0]  op,
//     input wire waiting,

//     output wire finish,
//     output wire [31:0] ALU_value
// );

ALU alu (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .RoB_clear(RoB_clear),
    .rdy_in(rdy_in),

    .vj(vj_ALU),
    .vk(vk_ALU),
    .imm(imm_ALU),
    .op(op_ALU),
    .waiting(waiting_ALU),

    .finish(ALU_finish_rdy),
    .ALU_value(ALU_value)
);

// module LoadStoreBuffer #(
//     parameter BTIS = `LSB_BITS,
//     parameter SIZE = `LSB_SIZE
// ) (
//     input wire clk_in,  // system clock signal
//     input wire rst_in,  // reset signal
//     input wire rdy_in,  // ready signal, pause cpu when low

//     input wire need_LSB,
//     input wire [6:0] opcode, // <output from decoder>
//     input wire [4:0] rd,
//     input wire [4:0] rs1,
//     input wire [4:0] rs2,
//     input wire [2:0] funct3,
//     input wire funct7,
//     input wire [31:0] imm,
//     input wire [31:0] pc,

//     // for memory
//     input wire [31:0] mem_result,
//     input wire mem_rdy,

//     // for register
//     input wire [`RoB_BITS-1:0] i_rs1_q,
//     input wire [`RoB_BITS-1:0] i_rs2_q,
//     input wire i_rs1_ready,  
//     input wire i_rs2_ready,  
//     input wire [31:0] i_rs1_value,
//     input wire [31:0] i_rs2_value,

//     // for RoB
//     input wire RoB_clear,
//     input wire issue_ready,
//     input wire [`RoB_BITS-1:0] RoB_head,
//     input wire [`RoB_BITS-1:0] RoB_tail,
//     input wire RoB_rdy_RS,
//     input wire [`RoB_BITS-1:0] RoB_id_RS,  
//     input wire [31:0] RoB_value_RS,
//     input wire RoB_rdy_LSB,
//     input wire [`RoB_BITS-1:0] RoB_id_LSB,
//     input wire [31:0] RoB_value_LSB,

//     output wire [`RoB_BITS-1:0] get_RoB_id_1,  // get value from RoB if q_i is not ready
//     output wire [`RoB_BITS-1:0] get_RoB_id_2,
//     input wire RoB_busy_1,
//     input wire RoB_busy_2,
//     input wire [31:0] get_RoB_value_1,
//     input wire [31:0] get_RoB_value_2,

//     output wire d_waiting,
//     output wire d_wr,
//     output wire [31:0] d_addr,
//     output wire [31:0] d_value,
//     output wire [2:0] d_len,

//     output wire LSB_finish_rdy,
//     output wire [`RoB_BITS-1:0] LSB_finish_id,
//     output wire [31:0] LSB_finish_value,

//     output wire full
// );

LoadStoreBuffer LSB (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .rdy_in(strict_rdy_in),

    .need_LSB(need_LSB),
    .opcode(opcode),
    .rd(rd),
    .rs1(rs1),
    .rs2(rs2),
    .funct3(funct3),
    .funct7(funct7),
    .imm(imm),
    .pc(pc),

    .mem_result(d_result),
    .mem_rdy(d_ready),

    .i_rs1_q(i_rs1_q),
    .i_rs2_q(i_rs2_q),
    .i_rs1_ready(i_rs1_ready),
    .i_rs2_ready(i_rs2_ready),
    .i_rs1_value(i_rs1_value),
    .i_rs2_value(i_rs2_value),

    .RoB_clear(RoB_clear),
    .issue_ready(issue_ready),
    .RoB_head(RoB_head),
    .RoB_tail(RoB_tail),
    .RoB_rdy_RS(RoB_rdy_RS),
    .RoB_id_RS(RoB_id_RS),
    .RoB_value_RS(RoB_value_RS),
    .RoB_rdy_LSB(RoB_rdy_LSB),
    .RoB_id_LSB(RoB_id_LSB),
    .RoB_value_LSB(RoB_value_LSB),

    .get_RoB_id_1(get_RoB_id_1),
    .get_RoB_id_2(get_RoB_id_2),
    .RoB_busy_1(RoB_busy_1),
    .RoB_busy_2(RoB_busy_2),
    .get_RoB_value_1(get_RoB_value_1),
    .get_RoB_value_2(get_RoB_value_2),

    .d_waiting(d_waiting),
    .d_wr(d_wr),
    .d_addr(d_addr),
    .d_value(d_value),
    .d_len(d_len),

    .LSB_finish_rdy(LSB_finish_rdy),
    .LSB_finish_id(LSB_finish_id),
    .LSB_finish_value(LSB_finish_value),

    .full(LSB_full)
);



endmodule