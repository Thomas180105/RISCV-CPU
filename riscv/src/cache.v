module Cache (
    input wire clk_in,  // system clock signal
    input wire rst_in,  // reset signal
    input wire RoB_clear,
    input wire rdy_in,  // ready signal, pause cpu when low

    input  wire [ 7:0] mem_din,   // data input bus
    output wire [ 7:0] mem_dout,  // data output bus
    output wire [31:0] mem_a,     // address bus (only 17:0 is used)
    output wire        mem_wr,    // write/read signal (1 for write)

    //instruction cache
    input wire i_waiting,  
    input wire [31:0] i_addr, 

    output wire [31:0] i_result,  // result of read 
    output wire i_ready,          // ready to return instruction result and accept new read request
    
    //data cache
    //<output from LSB>
    input wire d_waiting,     
    input wire [31:0] d_addr,  
    input wire [31:0] d_value, // value to be written
    input wire [2:0] d_len,    // length of data to be read/written
    input wire d_wr,           // write/read signal (1 for write) 
    //<input to LSB>
    output wire [31:0] d_result, 
    output wire d_ready
);
    
    reg state; // 0: vacant, 1: busy
    reg [31:0] current_addr; //assign by i_addr or d_addr
    
    wire i_hit;  
    wire [31:0] i_res;  
    wire i_wr;  

    //memory controller
    reg m_wr;  
    wire m_waiting = d_waiting || (i_hit ? 0 : i_waiting);// i.e d_waiting || !i_hit (since i_waiting eq 1 all the time)
    wire m_ready; 
    wire [31:0] m_res;  // result of read operation  
    reg [2:0] m_len;  
    reg [31:0] m_addr;  
    reg [31:0] m_value;  // value to be written
  
    //instruction cache
    assign i_result = i_hit ? i_res : m_res;
    assign i_wr = !d_waiting && state && m_ready && (i_addr == current_addr);
    assign i_ready = !d_waiting && (current_addr == i_addr) && (i_hit || (m_ready && !m_waiting));

    // always @(posedge clk_in) begin
    //     $display("i_ready=%b,d_waiting=%b, current_addr=%h, i_addr=%h, d_addr=%h, i_hit=%b, m_ready=%b, m_waiting=%b, i_waiting=%b",i_ready, d_waiting, current_addr, i_addr, d_addr, i_hit, m_ready, m_waiting, i_waiting);
    // end

    //data cache
    assign d_result = m_res;
    assign d_ready = (d_addr == current_addr) && m_ready && d_waiting;

    MemoryController mc (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .mem_din(mem_din),
        .mem_dout(mem_dout),
        .mem_a(mem_a),
        .mem_wr(mem_wr),

        .RoB_clear(RoB_clear),

        .waiting(m_waiting),
        .wr(m_wr),
        .len(m_len),
        .addr(m_addr),
        .value(m_value),

        .ready (m_ready),
        .result(m_res)
    );

    InstructionCache #(
        .IndexBit(2)
    ) icache (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .rdy_in(rdy_in),

        .wr(i_wr),
        .waiting(i_waiting),
        .addr(i_addr),
        .value(i_result),

        .hit(i_hit),
        .result(i_res)
    );

    always @(posedge clk_in) begin
        if (rst_in || RoB_clear) begin
            m_wr <= 0;
            m_len <= 0;
            m_addr <= 0;
            m_value <= 0;
            state <= 0;
            current_addr <= 0;
        end
        else if (rdy_in) begin
            case (state)
                1'b0: begin 
                    if (d_waiting) begin 
                        state <= 1;
                        m_wr <= d_wr;
                        m_len <= d_len;
                        m_addr <= d_addr;
                        m_value <= d_value;
                        current_addr <= d_addr;
                    end
                    else if (i_waiting) begin // note that this is "else if" not "if"!
                        if (i_hit) begin
                            current_addr <= i_addr;
                        end
                        else begin
                            state <= 1;
                            m_wr <= 0;
                            m_len <= 2;
                            m_addr <= i_addr;
                            m_value <= 0;
                            current_addr <= i_addr;
                        end
                    end                      
                end
                1'b1: begin                  
                    if (m_ready) begin
                        state = 0;
                    end
                end
            endcase
        end
    end


endmodule
