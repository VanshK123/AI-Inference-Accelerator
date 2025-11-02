// Formal verification properties for MAC array and control sequencer
module mac_assertions #(
    parameter int N = 32,
    parameter int M = 32
) (
    input logic clk,
    input logic rst_n,
    // MAC array signals
    input logic mac_start,
    input logic mac_done,
    input logic [1:0] precision_mode,
    input logic mac_overflow,
    input logic [31:0] mac_count,
    // Control sequencer signals
    input logic [2:0] seq_state,
    input logic inference_done,
    input logic inference_error,
    // Memory subsystem signals
    input logic dma_done,
    input logic dma_error
);

    // Property: MAC start implies eventually done
    property mac_completion;
        @(posedge clk) disable iff(!rst_n)
        mac_start |-> s_eventually(mac_done);
    endproperty
    assert property(mac_completion) else $error("MAC operation did not complete");

    // Property: No overflow when not computing
    property no_overflow_idle;
        @(posedge clk) disable iff(!rst_n)
        !mac_start && $past(!mac_start) |-> !mac_overflow;
    endproperty
    assert property(no_overflow_idle);

    // Property: MAC count only increments during computation
    property mac_count_monotonic;
        @(posedge clk) disable iff(!rst_n)
        mac_count >= $past(mac_count);
    endproperty
    assert property(mac_count_monotonic);

    // Property: Sequencer state machine is valid
    property sequencer_valid_states;
        @(posedge clk) disable iff(!rst_n)
        seq_state inside {3'b000, 3'b001, 3'b010, 3'b011, 3'b100, 3'b101, 3'b110, 3'b111};
    endproperty
    assert property(sequencer_valid_states);

    // Property: Inference error implies sequencer stops
    property error_handling;
        @(posedge clk) disable iff(!rst_n)
        inference_error |-> ##1 seq_state == 3'b000; // IDLE
    endproperty
    assert property(error_handling) else $error("Sequencer did not handle error correctly");

    // Property: DMA done without error
    property dma_completion;
        @(posedge clk) disable iff(!rst_n)
        dma_done |-> !dma_error;
    endproperty
    assert property(dma_completion) else $error("DMA completion with error");

    // Property: Inference done eventually if started
    property inference_completion;
        @(posedge clk) disable iff(!rst_n)
        (seq_state != 3'b000) |-> s_eventually(inference_done || inference_error);
    endproperty
    assert property(inference_completion);

    // Property: No deadlock - sequencer can always progress
    property no_deadlock;
        @(posedge clk) disable iff(!rst_n)
        (seq_state != 3'b000) |-> ##[1:100] (seq_state != $past(seq_state) || inference_done || inference_error);
    endproperty
    assert property(no_deadlock) else $error("Potential deadlock detected");

    // Property: Precision mode is valid
    property valid_precision;
        @(posedge clk) disable iff(!rst_n)
        precision_mode inside {2'b00, 2'b01, 2'b10};
    endproperty
    assert property(valid_precision);

    // Cover properties for functional coverage
    cover property(@(posedge clk) mac_start && precision_mode == 2'b00 && ##[1:1000] mac_done);
    cover property(@(posedge clk) mac_start && precision_mode == 2'b01 && ##[1:1000] mac_done);
    cover property(@(posedge clk) inference_done);
    cover property(@(posedge clk) dma_done);

endmodule
