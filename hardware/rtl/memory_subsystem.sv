module memory_subsystem(
    input  logic clk,
    input  logic rst,
    // AXI4-Stream slave for input
    input  logic s_axis_tvalid,
    output logic s_axis_tready,
    input  logic [63:0] s_axis_tdata,
    input  logic s_axis_tlast,
    // AXI4-Stream slave for output
    output logic m_axis_tvalid,
    input  logic m_axis_tready,
    output logic [63:0] m_axis_tdata,
    output logic m_axis_tlast,
    // AXI4 master to external memory
    output logic [31:0] m_axi_awaddr,
    output logic [7:0]  m_axi_awlen,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    output logic [63:0] m_axi_wdata,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready
);

    // simple dual-port BRAM scratchpad
    logic [63:0] bram [0:1023];
    logic [9:0] wr_ptr, rd_ptr;

    assign s_axis_tready = 1'b1;
    always_ff @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 0;
        end else if (s_axis_tvalid && s_axis_tready) begin
            bram[wr_ptr] <= s_axis_tdata;
            wr_ptr <= wr_ptr + 1;
        end
    end

    assign m_axis_tvalid = (rd_ptr != wr_ptr);
    assign m_axis_tdata  = bram[rd_ptr];
    assign m_axis_tlast  = 0;
    always_ff @(posedge clk) begin
        if (rst) rd_ptr <= 0;
        else if (m_axis_tready && m_axis_tvalid)
            rd_ptr <= rd_ptr + 1;
    end

    // simple AXI write for scatter-gather descriptor example
    assign m_axi_awaddr  = 32'h0;
    assign m_axi_awlen   = 0;
    assign m_axi_awvalid = 0;
    assign m_axi_wdata   = 64'h0;
    assign m_axi_wvalid  = 0;
    assign m_axi_bready  = 1'b1;
endmodule
