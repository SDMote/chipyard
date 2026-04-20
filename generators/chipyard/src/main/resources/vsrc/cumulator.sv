`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Alfonso Cortés
// 
// Create Date: 10.12.2025
// Design Name: sram_puf
// Module Name: cumulator
// Project Name: riscv
// Description: 
// 
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


///////////////////////////// Instantiation Template /////////////////////////////
//    cumulator #(
//        .MAX_CYCLES(250),   // 
//        .WIDTH(8),          // memory word size in bits
//        .DEPTH(256),        // memory number of words
//        .WORDS(16)          // number of words in the shift register
//        ) instance_name (
//        .clock(),       // 1 bit input: clock signal
//        .reset(),       // 1 bit input: reset signal
//        .address(),     // clog2(WIDTH) bits output: memory address
//        .data(),        // WIDTH bits input: memory data
//        .word_index(),  // position currently updating
//        .sums(),        // WORDS*WIDTH array output: current buffer content
//        .checkpoint(),  // WIDTH bits input: address checkpoint to start loading from
//        .load(),        // 1 bit input: load a new word into the shift register
//        .stop(),        // 1 bit input: wait for sram to reset
//        .shift()        // 1 bit input: clear registers, update checkpoint and continue
//    );   
//////////////////////////////////////////////////////////////////////////////////

module cumulator #(
    MAX_CYCLES = 127,
    WIDTH = 8,         // memory word size in bits
    DEPTH = 256,       // memory number of words
    WORDS = 16         // 
    )(
    clock,
    reset,
    address,    // memory address
    data,       // memory data
    sums,
    word_index,
    checkpoint, //
    load,
    stop,
    shift
    );
    
    localparam ADDRESS_SIZE = $clog2(DEPTH);
    localparam SUM_SIZE = $clog2(MAX_CYCLES+1);
    localparam REG_SIZE = WORDS * WIDTH;
    localparam BIT_IDX_SIZE = $clog2(WIDTH);
    localparam WORD_IDX_SIZE = $clog2(WORDS);
    localparam REG_IDX_SIZE = $clog2(REG_SIZE);
    input  logic clock;
    input  logic reset;
    output logic [ADDRESS_SIZE-1:0] address;
    input  logic [WIDTH-1:0] data;
    output logic [SUM_SIZE-1:0] sums [REG_SIZE-1:0];
    output logic [WORD_IDX_SIZE-1:0] word_index;
    input  logic [ADDRESS_SIZE-1:0] checkpoint;
    input  logic load;
    input  logic stop;
    input  logic shift;
    
    enum logic [1:0]{IDLE, LOAD, STOP} state, state_next;
    logic [SUM_SIZE-1:0] sums_next [REG_SIZE-1:0];
    logic [SUM_SIZE-1:0] sums_prev [REG_SIZE-1:0];
    logic [ADDRESS_SIZE-1:0] address_prev;
    logic [WORD_IDX_SIZE-1:0] word_index_next;
    logic [REG_IDX_SIZE-1:0] reg_index;
    
    
    always_ff @(posedge clock) begin
        if(reset) begin
            state <= IDLE;
            address_prev <= {ADDRESS_SIZE{1'b0}};
            word_index <= 0;
            for(int i=0; i<REG_SIZE; i++) begin
                 sums_prev[i] <= 0;
            end
        end
        else begin
            state <= state_next;
            address_prev <= address;
            word_index <= word_index_next;
            sums_prev <= sums_next;
        end
    end
    
    always_comb begin
        state_next = state;
        address = address_prev;
        word_index_next = word_index;
        sums = sums_prev;
        sums_next = sums_prev;
        case(state)
            IDLE: begin
                address = checkpoint;
                word_index_next = 0;
                for(int i=0; i<REG_SIZE; i++) begin
                     sums_next[i] = 0;
                end
                if(load)
                    state_next = LOAD;
            end
            LOAD: begin
                for(int i=0; i<WIDTH; i++) begin
                    sums[reg_index+i] = sums_prev[reg_index+i] + data[i];  
                end
                if(shift) begin     // clear sums and advance
                    word_index_next = 0;
                    for(int i=0; i<REG_SIZE; i++) begin
                        sums_next[i] = 0;  
                    end
                    address = address_prev + 1;
                end
                else begin
                    sums_next = sums;
                    if(stop) begin      // if last word
                        word_index_next = 0;
                        state_next = STOP;
                        address = checkpoint;
                    end
                    else begin
                        address = address_prev + 1;
                        word_index_next = word_index + 1;
                    end
                end
            end
            STOP: begin
                if(load) begin
                    state_next = LOAD;
                end
            end
            default:
                state_next = IDLE;
        endcase
        if(shift && stop) begin
            word_index_next = 0;
            for(int i=0; i<REG_SIZE; i++) begin
                sums_next[i] = 0;  
            end
            state_next = IDLE;
            address = checkpoint;
        end
    end
    
    assign reg_index = {word_index, {BIT_IDX_SIZE{1'b0}}};
    
endmodule