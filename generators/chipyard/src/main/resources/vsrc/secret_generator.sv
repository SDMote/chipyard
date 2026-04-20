`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Alfonso Cortés
// 
// Create Date: 17.02.2026
// Design Name: sram_puf
// Module Name: secret_generator
// Project Name: riscv
// Description: 
// 
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


///////////////////////////// Instantiation Template /////////////////////////////
//    secret_generator #(
//        .MAX_KEY_SIZE(128), // maximum size of derived key in bits
//        .MAX_CYCLES(127),   // maximum number of readouts
//        .METRIC_SIZE(3),    // significant figures in bit-unstability metrics
//        .WIDTH(8),          // memory word size in bits
//        .DEPTH(256),        // memory number of words
//        .WORDS(16)          // number of words in the shift register
//        ) instance_name (
//        .clock(),           // 1 bit input: clock signal
//        .reset(),           // 1 bit input: reset signal
//        .enable(),          // 1 bit input: start signal
//        .address(),         // clog2(WIDTH) bits output: memory address
//        .data(),            // WIDTH bits input: memory data
//        .start_address(),   // clog2(WIDTH) bits input: start memory address
//        .key_size(),        // configured key size in bits
//        .cycles(),          // configured number of power-on cycles
//        .sram_on(),         // 1 bit output:
//        .sram_rdy(),        // 1 bit input:
//        .key(),             // MAX_KEY_SIZE bits output: derivated key
//        .unstability(),     // clog2(MAX_KEY_SIZE)+(1<<METRIC_SIZE)-1 bits output: unstability metric
//        .done()             // 1 bit input: key is valid
//    );   
//////////////////////////////////////////////////////////////////////////////////

module secret_generator #(
    MAX_KEY_SIZE = 128,
    MAX_CYCLES = 127,
    METRIC_SIZE = 3,
    WIDTH = 8,         // memory word size in bits
    DEPTH = 256,       // memory number of words
    WORDS = 16         // 
    )(
    clock,
    reset,
    enable,
    address,
    data,       // memory data
    start_address,
    key_size,
    cycles,
    sram_on,
    sram_rdy,
    key,
    unstability,
    done
    );
    
    localparam ADDRESS_SIZE = $clog2(DEPTH);
    localparam KEY_INDX_SIZE = $clog2(MAX_KEY_SIZE+1);
    localparam COUNT_SIZE = $clog2(MAX_CYCLES+1);
    localparam UNSTABILITY_SIZE = $clog2(MAX_KEY_SIZE) + (1<<METRIC_SIZE) - 1;
    input  logic clock;
    input  logic reset;
    input  logic enable;
    output logic [ADDRESS_SIZE-1:0] address;
    input  logic [WIDTH-1:0] data;
    input  logic [ADDRESS_SIZE-1:0] start_address;
    input  logic [KEY_INDX_SIZE-1:0] key_size;
    input  logic [COUNT_SIZE-1:0] cycles;
    output logic sram_on;
    input  logic sram_rdy;
    output logic [MAX_KEY_SIZE-1:0] key;
    output logic [UNSTABILITY_SIZE-1:0] unstability;
    output logic done;

    localparam SUM_SIZE = $clog2(MAX_CYCLES+1);
    localparam REG_SIZE = WORDS * WIDTH;
    localparam WORD_IDX_SIZE = $clog2(WORDS);
    localparam BIT_IDX_SIZE = $clog2(WIDTH);
    localparam REG_IDX_SIZE = $clog2(REG_SIZE);
    localparam CNT_IDX_SIZE = $clog2(COUNT_SIZE);
    localparam WORD_CNT_SIZE = $clog2(MAX_KEY_SIZE>>BIT_IDX_SIZE);
    enum logic [1:0] {IDLE, RUN, OFF, DONE} state, state_next;
    logic [MAX_KEY_SIZE-1:0] key_next;
    logic [UNSTABILITY_SIZE-1:0] unstability_next;
    logic [ADDRESS_SIZE-1:0] checkpoint, checkpoint_next;
    logic [COUNT_SIZE-1:0] counter, counter_next;
    logic [WORD_CNT_SIZE-1:0] required_words, word_count, word_count_next;
    logic [SUM_SIZE-1:0] sums [REG_SIZE-1:0];
    logic [CNT_IDX_SIZE-1:0] divider;
    logic [METRIC_SIZE-1:0] bit_unstabilities [REG_SIZE-1:0];
    logic [WORD_IDX_SIZE-1:0] word_index;
    logic [KEY_INDX_SIZE-1:0] bit_count;
    logic last_cycle, load, shift, stop;
    
    assign last_cycle = counter==(cycles-1);
    assign required_words = ((key_size-1) >> BIT_IDX_SIZE);
    assign bit_count = word_count << BIT_IDX_SIZE;
    
    always_ff @(posedge clock) begin
        if (reset) begin
            state <= IDLE;
            checkpoint <= 0;
            counter <= 0;
            word_count <= 0;
            key <= {MAX_KEY_SIZE{1'b0}};
            unstability <= {UNSTABILITY_SIZE{1'b0}};
        end
        else begin
            state <= state_next;
            checkpoint <= checkpoint_next;
            counter <= counter_next;
            word_count <= word_count_next;
            key[MAX_KEY_SIZE-1:0] <= key_next[MAX_KEY_SIZE-1:0];
            unstability[UNSTABILITY_SIZE-1:0] <= unstability_next[UNSTABILITY_SIZE-1:0];
        end
    end
    
    always_comb begin
        state_next = state;
        checkpoint_next = checkpoint;
        counter_next = counter;
        word_count_next = word_count;
        key_next[MAX_KEY_SIZE-1:0] = key[MAX_KEY_SIZE-1:0];
        unstability_next[UNSTABILITY_SIZE-1:0] = unstability[UNSTABILITY_SIZE-1:0];
        load = 1'b0;
        stop = 1'b0;
        shift = 1'b0;
        sram_on = 1'b1;
        done = 1'b0;
        divider = 0;
        for (int i=COUNT_SIZE-1; i>=0; i--) begin
            if(cycles[i]) begin
                divider = i > METRIC_SIZE ? i-METRIC_SIZE : 0;
                break;
            end
        end
        for (int i=0; i<REG_SIZE; i++) begin
            bit_unstabilities[i] = sums[i] <= (cycles>>1) ? (sums[i]>>divider) : ((cycles - sums[i])>>divider);
        end
        case(state)
            IDLE: begin 
                checkpoint_next = start_address;
                if(enable && sram_rdy) begin
                    state_next = RUN;
                    load = 1'b1;
                end
            end
            RUN: begin
                if(word_index == WORDS-1 || (word_count+word_index) == required_words) begin
                    if(last_cycle) begin
                        for (int i=0; i<REG_SIZE; i++) begin
                            key_next[bit_count+i] = sums[i] <= (cycles>>1) ? 0 : 1;
                            if(bit_unstabilities[i] > 0)
                                unstability_next =  unstability_next + (1 << (bit_unstabilities[i]-1));
                        end
                        counter_next = 0;
                        shift = 1'b1;
                        if((word_count+word_index) == required_words) begin
                            state_next = DONE;
                            stop = 1'b1;
                            word_count_next = 0;
                        end
                        else begin
                            word_count_next = word_count + WORDS;
                            checkpoint_next = address;
                        end
                    end
                    else begin
                        state_next = OFF; 
                        stop = 1'b1;
                        sram_on = 1'b0;
                        counter_next = counter + 1;
                    end
                end
            end
            OFF: begin
                if(sram_rdy) begin
                    load = 1'b1;
                    state_next = RUN;
                end
                else begin
                    sram_on = 1'b0;
                end
            end
            DONE: begin
                checkpoint_next = start_address;
                done = 1'b1;
            end
            default:
                state_next = IDLE;
        endcase
        if(enable==1'b0) begin
            state_next = IDLE;
            key_next = {MAX_KEY_SIZE{1'b0}};
            unstability_next = {METRIC_SIZE{1'b0}};
            checkpoint_next = start_address;
            counter_next = 0;
            word_count_next = 0;
            shift = 1'b1;
            stop = 1'b1;
            done = 1'b0;
        end
    end
    
    cumulator #(
        .MAX_CYCLES(MAX_CYCLES),   // 
        .WIDTH(WIDTH),          // memory word size in bits
        .DEPTH(DEPTH),        // memory number of words
        .WORDS(WORDS)          // number of words in the shift register
        ) Buffer (
        .clock(clock),       // 1 bit input: clock signal
        .reset(reset),       // 1 bit input: reset signal
        .address(address),     // clog2(WIDTH) bits output: memory address
        .data(data),        // WIDTH bits input: memory data
        .word_index(word_index),  // position currently updating
        .sums(sums),        // WORDS*WIDTH array output: current buffer content
        .checkpoint(checkpoint),  // WIDTH bits input: address checkpoint to start loading from
        .load(load),        // 1 bit input: load a new word into the shift register
        .stop(stop),        // 1 bit output: shift register is full
        .shift(shift)        // 1 bit input: clear registers, update checkpoint and continue
    );   

endmodule
