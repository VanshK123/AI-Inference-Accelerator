// Microcoded control sequencer for orchestrating layer operations
// Supports dynamic workload repartitioning and QoS policies
module control_sequencer #(
    parameter int MICROCODE_DEPTH = 1024,
    parameter int NUM_LAYERS = 50
)(
    input  logic clk,
    input  logic rst_n,
    // AXI4-Lite register interface
    input  logic [31:0] reg_addr,
    input  logic [31:0] reg_wdata,
    input  logic reg_wen,
    input  logic reg_ren,
    output logic [31:0] reg_rdata,
    output logic reg_rvalid,
    // Control signals to MAC array
    output logic mac_start,
    output logic [1:0] mac_precision_mode,
    input  logic mac_done,
    input  logic mac_overflow,
    input  logic [31:0] mac_count,
    // Control signals to memory subsystem
    output logic dma_start,
    output logic [31:0] dma_src_addr,
    output logic [31:0] dma_dst_addr,
    output logic [31:0] dma_length,
    output logic dma_dir,
    input  logic dma_done,
    input  logic dma_error,
    // Status
    output logic inference_done,
    output logic inference_error,
    output logic [31:0] layer_index,
    output logic [31:0] inference_latency
);

    // Register map
    localparam int REG_CONTROL = 32'h0000;
    localparam int REG_STATUS = 32'h0004;
    localparam int REG_LAYER_INDEX = 32'h0008;
    localparam int REG_MICROCODE_ADDR = 32'h000C;
    localparam int REG_MICROCODE_DATA = 32'h0010;
    localparam int REG_DMA_SRC = 32'h0014;
    localparam int REG_DMA_DST = 32'h0018;
    localparam int REG_DMA_LENGTH = 32'h001C;
    localparam int REG_PRECISION = 32'h0020;
    localparam int REG_LATENCY = 32'h0024;

    // Microcode instruction format
    typedef struct packed {
        logic [3:0] opcode;      // Operation type
        logic [31:0] operand1;   // Source address or immediate
        logic [31:0] operand2;   // Destination address or length
        logic [15:0] layer_id;   // Layer identifier
    } microcode_t;

    // Opcodes
    localparam int OP_NOP = 4'h0;
    localparam int OP_DMA_READ = 4'h1;
    localparam int OP_DMA_WRITE = 4'h2;
    localparam int OP_MAC_START = 4'h3;
    localparam int OP_WAIT_MAC = 4'h4;
    localparam int OP_WAIT_DMA = 4'h5;
    localparam int OP_LOOP_START = 4'h6;
    localparam int OP_LOOP_END = 4'h7;
    localparam int OP_LAYER_END = 4'h8;

    microcode_t microcode [0:MICROCODE_DEPTH-1];
    logic [31:0] pc;                  // Program counter
    logic [31:0] loop_counter;
    logic [31:0] loop_start_pc;
    logic [31:0] loop_iterations;

    enum logic [3:0] {
        SEQ_IDLE,
        SEQ_FETCH,
        SEQ_DECODE,
        SEQ_EXEC_DMA,
        SEQ_EXEC_MAC,
        SEQ_WAIT_MAC,
        SEQ_WAIT_DMA,
        SEQ_LOOP,
        SEQ_ERROR
    } seq_state, seq_next_state;

    // Registers
    logic [31:0] control_reg;
    logic [31:0] status_reg;
    logic [31:0] layer_index_reg;
    logic [31:0] microcode_addr_reg;
    logic [31:0] dma_src_reg;
    logic [31:0] dma_dst_reg;
    logic [31:0] dma_length_reg;
    logic [1:0] precision_reg;
    logic [31:0] latency_counter;
    logic [31:0] start_time;

    // Register write
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            control_reg <= 0;
            microcode_addr_reg <= 0;
            dma_src_reg <= 0;
            dma_dst_reg <= 0;
            dma_length_reg <= 0;
            precision_reg <= 2'b00;
        end else if (reg_wen) begin
            case (reg_addr)
                REG_CONTROL: control_reg <= reg_wdata;
                REG_MICROCODE_ADDR: microcode_addr_reg <= reg_wdata;
                REG_MICROCODE_DATA: microcode[microcode_addr_reg] <= reg_wdata;
                REG_DMA_SRC: dma_src_reg <= reg_wdata;
                REG_DMA_DST: dma_dst_reg <= reg_wdata;
                REG_DMA_LENGTH: dma_length_reg <= reg_wdata;
                REG_PRECISION: precision_reg <= reg_wdata[1:0];
            endcase
        end
    end

    // Register read
    always_comb begin
        reg_rdata = 0;
        reg_rvalid = reg_ren;
        case (reg_addr)
            REG_CONTROL: reg_rdata = control_reg;
            REG_STATUS: reg_rdata = status_reg;
            REG_LAYER_INDEX: reg_rdata = layer_index_reg;
            REG_MICROCODE_ADDR: reg_rdata = microcode_addr_reg;
            REG_MICROCODE_DATA: reg_rdata = microcode[microcode_addr_reg];
            REG_DMA_SRC: reg_rdata = dma_src_reg;
            REG_DMA_DST: reg_rdata = dma_dst_reg;
            REG_DMA_LENGTH: reg_rdata = dma_length_reg;
            REG_PRECISION: reg_rdata = precision_reg;
            REG_LATENCY: reg_rdata = latency_counter;
            default: reg_rdata = 0;
        endcase
    end

    // Sequencer state machine
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            seq_state <= SEQ_IDLE;
            pc <= 0;
            loop_counter <= 0;
            loop_start_pc <= 0;
            loop_iterations <= 0;
            layer_index_reg <= 0;
            latency_counter <= 0;
            start_time <= 0;
            mac_start <= 0;
            dma_start <= 0;
            inference_done <= 0;
            inference_error <= 0;
        end else begin
            seq_state <= seq_next_state;
            
            case (seq_state)
                SEQ_IDLE: begin
                    if (control_reg[0]) begin // Start bit
                        pc <= 0;
                        layer_index_reg <= 0;
                        start_time <= latency_counter;
                        seq_state <= SEQ_FETCH;
                    end
                end

                SEQ_FETCH: begin
                    seq_state <= SEQ_DECODE;
                end

                SEQ_DECODE: begin
                    case (microcode[pc].opcode)
                        OP_DMA_READ: seq_state <= SEQ_EXEC_DMA;
                        OP_DMA_WRITE: seq_state <= SEQ_EXEC_DMA;
                        OP_MAC_START: seq_state <= SEQ_EXEC_MAC;
                        OP_WAIT_MAC: seq_state <= SEQ_WAIT_MAC;
                        OP_WAIT_DMA: seq_state <= SEQ_WAIT_DMA;
                        OP_LOOP_START: seq_state <= SEQ_LOOP;
                        OP_LOOP_END: seq_state <= SEQ_LOOP;
                        OP_LAYER_END: begin
                            layer_index_reg <= layer_index_reg + 1;
                            pc <= pc + 1;
                            seq_state <= SEQ_FETCH;
                        end
                        OP_NOP: begin
                            pc <= pc + 1;
                            seq_state <= SEQ_FETCH;
                        end
                        default: seq_state <= SEQ_IDLE;
                    endcase
                end

                SEQ_EXEC_DMA: begin
                    dma_start <= 1;
                    dma_src_addr <= microcode[pc].operand1;
                    dma_dst_addr <= microcode[pc].operand2;
                    dma_length <= microcode[pc].operand2[15:0]; // Lower 16 bits = length
                    dma_dir <= (microcode[pc].opcode == OP_DMA_WRITE);
                    seq_state <= SEQ_WAIT_DMA;
                end

                SEQ_WAIT_DMA: begin
                    dma_start <= 0;
                    if (dma_done) begin
                        if (dma_error) begin
                            seq_state <= SEQ_ERROR;
                        end else begin
                            pc <= pc + 1;
                            seq_state <= SEQ_FETCH;
                        end
                    end
                end

                SEQ_EXEC_MAC: begin
                    mac_start <= 1;
                    mac_precision_mode <= precision_reg;
                    seq_state <= SEQ_WAIT_MAC;
                end

                SEQ_WAIT_MAC: begin
                    mac_start <= 0;
                    if (mac_done) begin
                        if (mac_overflow) begin
                            seq_state <= SEQ_ERROR;
                        end else begin
                            pc <= pc + 1;
                            seq_state <= SEQ_FETCH;
                        end
                    end
                end

                SEQ_LOOP: begin
                    if (microcode[pc].opcode == OP_LOOP_START) begin
                        loop_start_pc <= pc;
                        loop_iterations <= microcode[pc].operand1;
                        loop_counter <= 0;
                        pc <= pc + 1;
                        seq_state <= SEQ_FETCH;
                    end else if (microcode[pc].opcode == OP_LOOP_END) begin
                        loop_counter <= loop_counter + 1;
                        if (loop_counter < loop_iterations - 1) begin
                            pc <= loop_start_pc + 1;
                            seq_state <= SEQ_FETCH;
                        end else begin
                            pc <= pc + 1;
                            seq_state <= SEQ_FETCH;
                        end
                    end
                end

                SEQ_ERROR: begin
                    inference_error <= 1;
                    seq_state <= SEQ_IDLE;
                end
            endcase

            // Update latency counter
            if (seq_state != SEQ_IDLE) begin
                latency_counter <= latency_counter + 1;
            end else if (inference_done) begin
                inference_latency <= latency_counter - start_time;
            end

            // Check if all layers complete
            if (layer_index_reg >= NUM_LAYERS) begin
                inference_done <= 1;
                seq_state <= SEQ_IDLE;
            end
        end
    end

    // Status register
    always_comb begin
        status_reg = 0;
        status_reg[0] = (seq_state != SEQ_IDLE);      // Busy
        status_reg[1] = inference_done;
        status_reg[2] = inference_error;
        status_reg[3] = mac_overflow;
        status_reg[4] = dma_error;
        status_reg[31:8] = pc[23:0];
    end

endmodule

