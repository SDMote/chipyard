`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Alfonso Cortés
// 
// Create Date: 02.17.2026
// Design Name: sram_puf
// Module Name: security_peripheral
// Project Name: riscv
// Description: 
// 
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


///////////////////////////// Instantiation Template /////////////////////////////
//    security_peripheral #(
//        .MAX_KEY_SIZE(128), // maximum size of derived key in bits
//        .MAX_CYCLES(127),   // maximum number of power-on cycles
//        .METRIC_SIZE(3),    // significant figures in bit-unstability metrics
//        .WORDS(4)           // number of memory words read at each power-on cycle
//        ) instance_name (
//        .clock(),           // 1 bit input: clock signal
//        .reset(),           // 1 bit input: reset signal
//        .key_size(),        // 
//        .cycles(),          // 
//        .start_address(),   // 
//        .start(),           // 1 bit input: start signal
//        .key_0(),           // BUS_WIDTH bits output: LSB of the derivated key
//        .key_1(),           // BUS_WIDTH bits output: part of the derivated key
//        .key_2(),           // BUS_WIDTH bits output: part of the derivated key
//        .key_3(),           // BUS_WIDTH bits output: MSB of the derivated key
//        .unstability(),     // clog2(MAX_KEY_SIZE)+(1<<METRIC_SIZE)-1 bits output: unstability metric
//        .valid(),           // 1 bit input: key valid flag
//        .read_data(),       // 
//        .sram_on(),         // 
//        .sram_rdy()         // 
//    );
//////////////////////////////////////////////////////////////////////////////////

module SecurityPeripheral #(
    MAX_CYCLES = 127,    // maximum number of power-on cycles
    METRIC_SIZE = 4,
    WORDS = 4
    )(
    clock,
    reset,
    key_size,
    cycles,
    start_address,
    start,
    key_0,
    key_1,
    key_2,
    key_3,
    unstability,
    busy,
    valid,
    read_data,
    sram_on,
    sram_rdy
    );
        
    localparam MAX_KEY_SIZE = 128;  // maximum size of generated key in bits
    localparam BUS_WIDTH = 32;      // width of the system bus
    localparam MEMORY_WIDTH = 8;
    localparam MEMORY_DEPTH = 256;
    localparam ADDRESS_SIZE = $clog2(MEMORY_DEPTH);
    localparam KEY_INDX_SIZE = $clog2(MAX_KEY_SIZE+1);
    localparam COUNT_SIZE = $clog2(MAX_CYCLES+1);
    localparam UNSTABILITY_SIZE = $clog2(MAX_KEY_SIZE) + (1<<METRIC_SIZE) - 1;
    // Ports
    input  logic clock;
    input  logic reset;
    input  logic start;
    input  logic [KEY_INDX_SIZE-1:0] key_size;
    input  logic [COUNT_SIZE-1:0] cycles;
    input  logic [ADDRESS_SIZE-1:0] start_address;
    output logic [MEMORY_WIDTH-1:0] read_data;
    output logic sram_on;
    input  logic sram_rdy;
    output logic [BUS_WIDTH-1:0] key_0;
    output logic [BUS_WIDTH-1:0] key_1;
    output logic [BUS_WIDTH-1:0] key_2;
    output logic [BUS_WIDTH-1:0] key_3;
    output logic [UNSTABILITY_SIZE-1:0] unstability;
    output logic busy;
    output logic valid;
    
    logic [KEY_INDX_SIZE-1:0] key_size_reg;
    logic [COUNT_SIZE-1:0] cycles_reg;
    logic [ADDRESS_SIZE-1:0] start_address_reg;
    logic [ADDRESS_SIZE-1:0] address;
    logic [MAX_KEY_SIZE-1:0] key, new_key;
    logic [UNSTABILITY_SIZE-1:0] new_unstability;
    logic enable;
    logic start_reg;
    logic done;
    
    enum logic [1:0] {IDLE, RUN, SRAM} state;
    assign key_0 = key[1*BUS_WIDTH-1:0*BUS_WIDTH];
    assign key_1 = key[2*BUS_WIDTH-1:1*BUS_WIDTH];
    assign key_2 = key[3*BUS_WIDTH-1:2*BUS_WIDTH];
    assign key_3 = key[4*BUS_WIDTH-1:3*BUS_WIDTH];
    assign busy = state != IDLE;
    
    always_ff @(posedge clock) begin
        if (reset) begin
            state <= IDLE;
            enable <= 1'b0;
            start_reg <= 1'b0;
            key <= {MAX_KEY_SIZE{1'bx}};
            unstability <= {UNSTABILITY_SIZE{1'bx}};
            start_address_reg <= 0;
            cycles_reg <= 0;    
            key_size_reg <= 0;      
        end
        else begin
            start_reg <= start;
            if(start==1'b1 && start_reg==1'b0) begin 
                start_address_reg <= start_address;
                cycles_reg <= cycles;    
                key_size_reg <= key_size;     
            end
            case(state)
                IDLE: begin
                    if(start==1'b1 && start_reg==1'b0) begin
                        state <= SRAM;
                        enable <= 1'b0;
                        valid <= 1'b0;
                        key <= {MAX_KEY_SIZE{1'bx}};
                        unstability <= {UNSTABILITY_SIZE{1'bx}};
                    end
                end
                SRAM: begin
                    if(sram_rdy) begin
                        state <= RUN; 
                    end
                end
                RUN: begin
                    enable <= 1'b1;
                    if(start==1'b1 && start_reg==1'b0) begin
                        state <= SRAM; 
                        enable <= 1'b0;
                        valid <= 1'b0;
                        key <= {MAX_KEY_SIZE{1'bx}};
                        unstability <= {UNSTABILITY_SIZE{1'bx}};
                    end
                    if(done) begin
                        state <= IDLE;
                        key[MAX_KEY_SIZE-1:0] <= new_key[MAX_KEY_SIZE-1:0];
                        unstability <= new_unstability;
                        valid <= 1'b1;
                    end
                end
                default:
                    state <= IDLE;
            endcase
        end
    end
    
    
    secret_generator #(
        .MAX_KEY_SIZE(MAX_KEY_SIZE),  // maximum size of derived key in bits
        .MAX_CYCLES(MAX_CYCLES),     // maximum number of power-on cycles
        .METRIC_SIZE(METRIC_SIZE),    // significant figures in bit-unstability metrics
        .WIDTH(MEMORY_WIDTH),          // memory word size in bits
        .DEPTH(MEMORY_DEPTH),        // memory number of words
        .WORDS(WORDS)          // number of words in the shift register
        ) Control (
        .clock(clock),
        .reset(reset),
        .enable(enable),          // 1 bit input: start signal
        .address(address),         // clog2(WIDTH) bits output: memory address
        .data(read_data),            // WIDTH bits input: memory data
        .start_address(start_address_reg),   // clog2(WIDTH) bits input: start memory address
        .key_size(key_size_reg),    // configured key size in bits
        .cycles(cycles_reg),      // configured number of power-on cycles
        .sram_on(sram_on),         // 1 bit output:
        .sram_rdy(sram_rdy),        // 1 bit input:
        .key(new_key[MAX_KEY_SIZE-1:0]),         // MAX_KEY_SIZE bits output: derivated key
        .unstability(new_unstability),     // clog2(MAX_KEY_SIZE) + clog2(MAX_CYCLES/2) bits output: unstability metric
        .done(done)         // 1 bit output: key is valid
    );

    RM_IHPSG13_1P_256x8_c3_bm_bist Memory (
        .A_ADDR(address),
        .A_CLK(clock),
        .A_DIN('d0),
        .A_DOUT(read_data),
        .A_MEN(sram_on),
        .A_WEN(1'b0),
        .A_REN(1'b1),
        .A_BM({8{1'b1}}),
        .A_DLY(1'b1),       //  must always be 1
        .A_BIST_EN(1'b0),   // disable BIST
        .A_BIST_CLK(1'b0),
        .A_BIST_MEN(1'b0),
        .A_BIST_WEN(1'b0),
        .A_BIST_REN(1'b0),
        .A_BIST_ADDR({8{1'b0}}),
        .A_BIST_DIN({8{1'b0}}),
        .A_BIST_BM({8{1'b0}})
    );
    
endmodule
