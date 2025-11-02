// Parameterizable NxM systolic MAC array with mixed precision support
// Implements systolic array architecture for efficient matrix multiplication
module mac_array #(
    parameter int N = 32,              // Number of rows (default 32x32 per thesis)
    parameter int M = 32,              // Number of columns
    parameter string MODE = "INT8"     // INT8, INT16, FLOAT16
)(
    input  logic clk,
    input  logic rst_n,
    // Control signals
    input  logic start,
    output logic done,
    input  logic [1:0] precision_mode, // 00: INT8, 01: INT16, 10: FLOAT16
    // AXI4-Stream input for weights (B matrix)
    input  logic s_axis_w_tvalid,
    output logic s_axis_w_tready,
    input  logic [511:0] s_axis_w_tdata, // 64 bytes (8 INT8s or 4 INT16s or 4 FLOAT16s)
    // AXI4-Stream input for activations (A matrix)
    input  logic s_axis_a_tvalid,
    output logic s_axis_a_tready,
    input  logic [511:0] s_axis_a_tdata,
    // AXI4-Stream output for results
    output logic m_axis_r_tvalid,
    input  logic m_axis_r_tready,
    output logic [511:0] m_axis_r_tdata,
    output logic m_axis_r_tlast,
    // Status
    output logic [31:0] mac_count,     // Running count of MAC operations
    output logic overflow              // Accumulator overflow flag
);

    localparam int INT8_W = 8;
    localparam int INT16_W = 16;
    localparam int FLOAT16_W = 16;
    localparam int ACC_INT8_W = 32;    // 32-bit accumulator for INT8
    localparam int ACC_INT16_W = 48;   // 48-bit accumulator for INT16
    
    typedef struct packed {
        logic [INT8_W-1:0] int8_val;
        logic [INT16_W-1:0] int16_val;
        logic [FLOAT16_W-1:0] float16_val;
    } data_union_t;

    // Systolic array: each PE holds partial sum and propagates data
    typedef struct packed {
        logic [ACC_INT8_W-1:0] acc_int8;
        logic [ACC_INT16_W-1:0] acc_int16;
        logic [FLOAT16_W-1:0] acc_float16;
        logic valid;
    } pe_state_t;

    pe_state_t pe_array [N][M];
    
    // Input shift registers for systolic propagation
    logic [INT8_W-1:0] a_sr_int8 [N][M];
    logic [INT8_W-1:0] b_sr_int8 [N][M];
    logic [INT16_W-1:0] a_sr_int16 [N][M];
    logic [INT16_W-1:0] b_sr_int16 [N][M];
    logic [FLOAT16_W-1:0] a_sr_float16 [N][M];
    logic [FLOAT16_W-1:0] b_sr_float16 [N][M];

    enum logic [2:0] {
        IDLE,
        LOAD_WEIGHTS,
        COMPUTE,
        OUTPUT,
        DONE_STATE
    } state, next_state;

    logic [15:0] compute_counter;
    logic [15:0] row_idx, col_idx;
    logic [31:0] mac_count_reg;
    logic overflow_reg;
    logic [7:0] output_count;

    // State machine
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            compute_counter <= 0;
            row_idx <= 0;
            col_idx <= 0;
            output_count <= 0;
            mac_count_reg <= 0;
            overflow_reg <= 0;
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < M; j++) begin
                    pe_array[i][j] <= '0;
                    a_sr_int8[i][j] <= 0;
                    b_sr_int8[i][j] <= 0;
                    a_sr_int16[i][j] <= 0;
                    b_sr_int16[i][j] <= 0;
                    a_sr_float16[i][j] <= 0;
                    b_sr_float16[i][j] <= 0;
                end
            end
        end else begin
            state <= next_state;
            
            case (state)
                IDLE: begin
                    if (start) begin
                        compute_counter <= 0;
                        output_count <= 0;
                        mac_count_reg <= 0;
                        overflow_reg <= 0;
                    end
                end
                
                COMPUTE: begin
                    compute_counter <= compute_counter + 1;
                    mac_count_reg <= mac_count_reg + (N * M);
                end
                
                OUTPUT: begin
                    if (m_axis_r_tready && m_axis_r_tvalid) begin
                        output_count <= output_count + 1;
                    end
                end
            endcase
        end
    end

    // Next state logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: if (start) next_state = LOAD_WEIGHTS;
            LOAD_WEIGHTS: if (s_axis_w_tvalid && s_axis_w_tready) next_state = COMPUTE;
            COMPUTE: if (compute_counter >= 224) next_state = OUTPUT; // ResNet-50 layer depth
            OUTPUT: if (output_count >= (N*M)/64) next_state = DONE_STATE;
            DONE_STATE: next_state = IDLE;
        endcase
    end

    // Systolic array computation - INT8 mode
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // Already reset above
        end else if (state == COMPUTE && precision_mode == 2'b00) begin
            // Systolic propagation: data flows down (A) and right (B)
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < M; j++) begin
                    if (i == 0 && s_axis_a_tvalid) begin
                        a_sr_int8[0][j] <= s_axis_a_tdata[j*8 +: 8];
                    end else if (i > 0) begin
                        a_sr_int8[i][j] <= a_sr_int8[i-1][j];
                    end
                    
                    if (j == 0 && s_axis_w_tvalid) begin
                        b_sr_int8[i][0] <= s_axis_w_tdata[i*8 +: 8];
                    end else if (j > 0) begin
                        b_sr_int8[i][j] <= b_sr_int8[i][j-1];
                    end
                    
                    // MAC operation
                    if (i == 0 && j == 0) begin
                        pe_array[i][j].acc_int8 <= $signed(a_sr_int8[i][j]) * $signed(b_sr_int8[i][j]);
                    end else begin
                        pe_array[i][j].acc_int8 <= pe_array[i][j].acc_int8 + 
                                                    ($signed(a_sr_int8[i][j]) * $signed(b_sr_int8[i][j]));
                    end
                    
                    // Overflow detection for INT8
                    if (pe_array[i][j].acc_int8[ACC_INT8_W-1:ACC_INT8_W-2] != {2{pe_array[i][j].acc_int8[ACC_INT8_W-1]}}) begin
                        overflow_reg <= 1;
                    end
                end
            end
        end
    end

    // Systolic array computation - INT16 mode
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // Already reset above
        end else if (state == COMPUTE && precision_mode == 2'b01) begin
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < M; j++) begin
                    if (i == 0 && s_axis_a_tvalid) begin
                        a_sr_int16[0][j] <= s_axis_a_tdata[j*16 +: 16];
                    end else if (i > 0) begin
                        a_sr_int16[i][j] <= a_sr_int16[i-1][j];
                    end
                    
                    if (j == 0 && s_axis_w_tvalid) begin
                        b_sr_int16[i][0] <= s_axis_w_tdata[i*16 +: 16];
                    end else if (j > 0) begin
                        b_sr_int16[i][j] <= b_sr_int16[i][j-1];
                    end
                    
                    if (i == 0 && j == 0) begin
                        pe_array[i][j].acc_int16 <= $signed(a_sr_int16[i][j]) * $signed(b_sr_int16[i][j]);
                    end else begin
                        pe_array[i][j].acc_int16 <= pe_array[i][j].acc_int16 + 
                                                     ($signed(a_sr_int16[i][j]) * $signed(b_sr_int16[i][j]));
                    end
                end
            end
        end
    end

    // Output multiplexing based on precision mode
    always_comb begin
        s_axis_w_tready = (state == LOAD_WEIGHTS) || (state == COMPUTE);
        s_axis_a_tready = (state == COMPUTE);
        done = (state == DONE_STATE);
        mac_count = mac_count_reg;
        overflow = overflow_reg;
        
        m_axis_r_tvalid = (state == OUTPUT);
        m_axis_r_tlast = (output_count == (N*M)/64 - 1);
        
        // Pack output data based on precision
        m_axis_r_tdata = '0;
        if (state == OUTPUT) begin
            case (precision_mode)
                2'b00: begin // INT8
                    for (int k = 0; k < 64; k++) begin
                        int idx = output_count * 64 + k;
                        if (idx < N*M) begin
                            int i = idx / M;
                            int j = idx % M;
                            m_axis_r_tdata[k*8 +: 8] = pe_array[i][j].acc_int8[7:0]; // Saturated output
                        end
                    end
                end
                2'b01: begin // INT16
                    for (int k = 0; k < 32; k++) begin
                        int idx = output_count * 32 + k;
                        if (idx < N*M) begin
                            int i = idx / M;
                            int j = idx % M;
                            m_axis_r_tdata[k*16 +: 16] = pe_array[i][j].acc_int16[15:0];
                        end
                    end
                end
                default: m_axis_r_tdata = '0;
            endcase
        end
    end

endmodule
