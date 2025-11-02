// Hierarchical memory subsystem with dual-port BRAM scratchpad and DMA engine
module memory_subsystem #(
    parameter int SCRATCHPAD_DEPTH = 4096,  // 4K entries = 256KB @ 64-bit
    parameter int NUM_BANKS = 8              // Banked memory for parallel access
)(
    input  logic clk,
    input  logic rst_n,
    // AXI4-Stream from MAC array (results)
    input  logic s_axis_tvalid,
    output logic s_axis_tready,
    input  logic [511:0] s_axis_tdata,
    input  logic s_axis_tlast,
    // AXI4-Stream to MAC array (activations)
    output logic m_axis_tvalid,
    input  logic m_axis_tready,
    output logic [511:0] m_axis_tdata,
    output logic m_axis_tlast,
    // AXI4 master to external memory (HBM/DDR)
    // Write address channel
    output logic [31:0]  m_axi_awaddr,
    output logic [7:0]   m_axi_awlen,
    output logic [2:0]   m_axi_awsize,
    output logic [1:0]   m_axi_awburst,
    output logic         m_axi_awvalid,
    input  logic         m_axi_awready,
    // Write data channel
    output logic [511:0] m_axi_wdata,
    output logic [63:0]  m_axi_wstrb,
    output logic         m_axi_wlast,
    output logic         m_axi_wvalid,
    input  logic         m_axi_wready,
    // Write response channel
    input  logic [1:0]   m_axi_bresp,
    input  logic         m_axi_bvalid,
    output logic         m_axi_bready,
    // Read address channel
    output logic [31:0]  m_axi_araddr,
    output logic [7:0]   m_axi_arlen,
    output logic [2:0]   m_axi_arsize,
    output logic [1:0]   m_axi_arburst,
    output logic         m_axi_arvalid,
    input  logic         m_axi_arready,
    // Read data channel
    input  logic [511:0] m_axi_rdata,
    input  logic [1:0]   m_axi_rresp,
    input  logic         m_axi_rlast,
    input  logic         m_axi_rvalid,
    output logic         m_axi_rready,
    // Control interface from sequencer
    input  logic dma_start,
    input  logic [31:0] dma_src_addr,
    input  logic [31:0] dma_dst_addr,
    input  logic [31:0] dma_length,
    input  logic dma_dir,  // 0: read from external, 1: write to external
    output logic dma_done,
    output logic dma_error
);

    localparam int BANK_ADDR_BITS = $clog2(SCRATCHPAD_DEPTH / NUM_BANKS);
    
    // Dual-port BRAM banks
    typedef logic [511:0] data_t;
    data_t bram_bank [NUM_BANKS][0:(SCRATCHPAD_DEPTH/NUM_BANKS)-1];
    
    // Bank address decoding
    logic [2:0] write_bank;
    logic [2:0] read_bank;
    logic [BANK_ADDR_BITS-1:0] write_addr;
    logic [BANK_ADDR_BITS-1:0] read_addr;
    
    // Write/read pointers and control
    logic [15:0] write_ptr;
    logic [15:0] read_ptr;
    logic [15:0] write_count;
    logic [15:0] read_count;
    logic write_en;
    logic read_en;
    
    // AXI4 write state machine
    enum logic [2:0] {
        DMA_IDLE,
        DMA_WRITE_ADDR,
        DMA_WRITE_DATA,
        DMA_WRITE_RESP,
        DMA_READ_ADDR,
        DMA_READ_DATA
    } dma_state, dma_next_state;
    
    logic [31:0] dma_addr_reg;
    logic [31:0] dma_length_reg;
    logic [7:0]  dma_burst_cnt;
    logic [31:0] dma_words_transferred;
    
    // Scratchpad write from MAC array
    assign write_bank = write_ptr[2:0];
    assign write_addr = write_ptr[15:3];
    assign write_en = s_axis_tvalid && s_axis_tready;
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            write_ptr <= 0;
            write_count <= 0;
        end else begin
            if (write_en) begin
                bram_bank[write_bank][write_addr] <= s_axis_tdata;
                write_ptr <= write_ptr + 1;
                write_count <= write_count + 1;
            end
        end
    end
    
    assign s_axis_tready = (write_count < SCRATCHPAD_DEPTH);
    
    // Scratchpad read to MAC array
    assign read_bank = read_ptr[2:0];
    assign read_addr = read_ptr[15:3];
    assign read_en = m_axis_tready && m_axis_tvalid;
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            read_ptr <= 0;
            read_count <= 0;
        end else begin
            if (read_en) begin
                read_ptr <= read_ptr + 1;
                read_count <= read_count + 1;
            end
        end
    end
    
    assign m_axis_tvalid = (read_count < write_count);
    assign m_axis_tdata = bram_bank[read_bank][read_addr];
    assign m_axis_tlast = (read_count == write_count - 1);
    
    // DMA state machine
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            dma_state <= DMA_IDLE;
            dma_addr_reg <= 0;
            dma_length_reg <= 0;
            dma_burst_cnt <= 0;
            dma_words_transferred <= 0;
        end else begin
            dma_state <= dma_next_state;
            
            case (dma_state)
                DMA_IDLE: begin
                    if (dma_start) begin
                        dma_addr_reg <= dma_dir ? dma_dst_addr : dma_src_addr;
                        dma_length_reg <= dma_length;
                        dma_burst_cnt <= 0;
                        dma_words_transferred <= 0;
                    end
                end
                
                DMA_WRITE_ADDR: begin
                    if (m_axi_awready && m_axi_awvalid) begin
                        dma_addr_reg <= dma_addr_reg + (64 * (dma_burst_cnt + 1));
                    end
                end
                
                DMA_WRITE_DATA: begin
                    if (m_axi_wready && m_axi_wvalid) begin
                        dma_burst_cnt <= dma_burst_cnt + 1;
                        dma_words_transferred <= dma_words_transferred + 1;
                        if (m_axi_wlast) begin
                            dma_burst_cnt <= 0;
                        end
                    end
                end
                
                DMA_READ_ADDR: begin
                    if (m_axi_arready && m_axi_arvalid) begin
                        dma_addr_reg <= dma_addr_reg + (64 * (dma_burst_cnt + 1));
                    end
                end
                
                DMA_READ_DATA: begin
                    if (m_axi_rready && m_axi_rvalid) begin
                        dma_burst_cnt <= dma_burst_cnt + 1;
                        dma_words_transferred <= dma_words_transferred + 1;
                        if (m_axi_rlast) begin
                            dma_burst_cnt <= 0;
                        end
                    end
                end
            endcase
        end
    end
    
    // DMA next state logic
    always_comb begin
        dma_next_state = dma_state;
        dma_done = 1'b0;
        dma_error = 1'b0;
        
        case (dma_state)
            DMA_IDLE: begin
                if (dma_start) begin
                    dma_next_state = dma_dir ? DMA_WRITE_ADDR : DMA_READ_ADDR;
                end
            end
            
            DMA_WRITE_ADDR: begin
                if (m_axi_awready && m_axi_awvalid) begin
                    dma_next_state = DMA_WRITE_DATA;
                end
            end
            
            DMA_WRITE_DATA: begin
                if (m_axi_wready && m_axi_wvalid && m_axi_wlast) begin
                    if (dma_words_transferred >= dma_length_reg) begin
                        dma_next_state = DMA_WRITE_RESP;
                    end else begin
                        dma_next_state = DMA_WRITE_ADDR; // Next burst
                    end
                end
            end
            
            DMA_WRITE_RESP: begin
                if (m_axi_bvalid && m_axi_bready) begin
                    if (m_axi_bresp != 2'b00) begin
                        dma_error = 1'b1;
                    end
                    dma_done = 1'b1;
                    dma_next_state = DMA_IDLE;
                end
            end
            
            DMA_READ_ADDR: begin
                if (m_axi_arready && m_axi_arvalid) begin
                    dma_next_state = DMA_READ_DATA;
                end
            end
            
            DMA_READ_DATA: begin
                if (m_axi_rready && m_axi_rvalid && m_axi_rlast) begin
                    if (m_axi_rresp != 2'b00) begin
                        dma_error = 1'b1;
                    end
                    if (dma_words_transferred >= dma_length_reg) begin
                        dma_done = 1'b1;
                        dma_next_state = DMA_IDLE;
                    end else begin
                        dma_next_state = DMA_READ_ADDR; // Next burst
                    end
                end
            end
        endcase
    end
    
    // AXI4 write address channel
    assign m_axi_awaddr = dma_addr_reg;
    assign m_axi_awlen = 8'd15; // 16-beat burst
    assign m_axi_awsize = 3'b110; // 64 bytes (512 bits)
    assign m_axi_awburst = 2'b01; // INCR
    assign m_axi_awvalid = (dma_state == DMA_WRITE_ADDR);
    
    // AXI4 write data channel
    assign m_axi_wdata = bram_bank[read_bank][read_addr]; // Read from scratchpad
    assign m_axi_wstrb = 64'hFFFFFFFF_FFFFFFFF;
    assign m_axi_wlast = (dma_burst_cnt == 15);
    assign m_axi_wvalid = (dma_state == DMA_WRITE_DATA);
    
    // AXI4 write response channel
    assign m_axi_bready = (dma_state == DMA_WRITE_RESP);
    
    // AXI4 read address channel
    assign m_axi_araddr = dma_addr_reg;
    assign m_axi_arlen = 8'd15;
    assign m_axi_arsize = 3'b110;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arvalid = (dma_state == DMA_READ_ADDR);
    
    // AXI4 read data channel
    assign m_axi_rready = (dma_state == DMA_READ_DATA);
    
    // Write external data to scratchpad when reading
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // Reset handled above
        end else if (m_axi_rready && m_axi_rvalid && (dma_state == DMA_READ_DATA)) begin
            bram_bank[write_bank][write_addr] <= m_axi_rdata;
            write_ptr <= write_ptr + 1;
        end
    end

endmodule
