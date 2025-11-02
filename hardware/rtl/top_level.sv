// Top-level AI Inference Accelerator integrating all subsystems
module top_level #(
    parameter int BASE_ADDR = 32'h0000_0000,
    parameter int INTR_LINE = 0,
    parameter int MAC_N = 32,
    parameter int MAC_M = 32
)(
    input  logic clk,
    input  logic rst_n,
    // AXI4-Lite control plane
    input  logic [31:0]  s_axi_awaddr,
    input  logic [2:0]   s_axi_awprot,
    input  logic         s_axi_awvalid,
    output logic         s_axi_awready,
    input  logic [31:0]  s_axi_wdata,
    input  logic [3:0]   s_axi_wstrb,
    input  logic         s_axi_wvalid,
    output logic         s_axi_wready,
    output logic [1:0]   s_axi_bresp,
    output logic         s_axi_bvalid,
    input  logic         s_axi_bready,
    input  logic [31:0]  s_axi_araddr,
    input  logic [2:0]   s_axi_arprot,
    input  logic         s_axi_arvalid,
    output logic         s_axi_arready,
    output logic [31:0]  s_axi_rdata,
    output logic [1:0]   s_axi_rresp,
    output logic         s_axi_rvalid,
    input  logic         s_axi_rready,
    // AXI4-Stream data plane (for direct data injection if needed)
    input  logic         s_axis_tvalid,
    output logic         s_axis_tready,
    input  logic [511:0] s_axis_tdata,
    input  logic         s_axis_tlast,
    output logic         m_axis_tvalid,
    input  logic         m_axis_tready,
    output logic [511:0] m_axis_tdata,
    output logic         m_axis_tlast,
    // AXI4 master to external memory (HBM/DDR)
    output logic [31:0]  m_axi_awaddr,
    output logic [7:0]   m_axi_awlen,
    output logic [2:0]   m_axi_awsize,
    output logic [1:0]   m_axi_awburst,
    output logic         m_axi_awvalid,
    input  logic         m_axi_awready,
    output logic [511:0] m_axi_wdata,
    output logic [63:0]  m_axi_wstrb,
    output logic         m_axi_wlast,
    output logic         m_axi_wvalid,
    input  logic         m_axi_wready,
    input  logic [1:0]   m_axi_bresp,
    input  logic         m_axi_bvalid,
    output logic         m_axi_bready,
    output logic [31:0]  m_axi_araddr,
    output logic [7:0]   m_axi_arlen,
    output logic [2:0]   m_axi_arsize,
    output logic [1:0]   m_axi_arburst,
    output logic         m_axi_arvalid,
    input  logic         m_axi_arready,
    input  logic [511:0] m_axi_rdata,
    input  logic [1:0]   m_axi_rresp,
    input  logic         m_axi_rlast,
    input  logic         m_axi_rvalid,
    output logic         m_axi_rready,
    // PCIe interface (simplified - actual implementation would use IP)
    input  logic         pcie_clk,
    input  logic         pcie_rst_n,
    output logic [3:0]   pcie_tx,
    input  logic [3:0]   pcie_rx,
    // Interrupt
    output logic         interrupt
);

    // Internal signals
    logic [31:0] reg_addr;
    logic [31:0] reg_wdata;
    logic reg_wen;
    logic reg_ren;
    logic [31:0] reg_rdata;
    logic reg_rvalid;

    logic mac_start;
    logic mac_done;
    logic [1:0] mac_precision_mode;
    logic mac_overflow;
    logic [31:0] mac_count;

    logic dma_start;
    logic [31:0] dma_src_addr;
    logic [31:0] dma_dst_addr;
    logic [31:0] dma_length;
    logic dma_dir;
    logic dma_done;
    logic dma_error;

    logic inference_done;
    logic inference_error;
    logic [31:0] layer_index;
    logic [31:0] inference_latency;

    // AXI4-Lite slave interface
    axi4_lite_slave u_axi4_lite (
        .aclk(clk),
        .aresetn(rst_n),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .reg_addr(reg_addr),
        .reg_wdata(reg_wdata),
        .reg_wen(reg_wen),
        .reg_ren(reg_ren),
        .reg_rdata(reg_rdata),
        .reg_rvalid(reg_rvalid)
    );

    // Control sequencer
    control_sequencer u_sequencer (
        .clk(clk),
        .rst_n(rst_n),
        .reg_addr(reg_addr),
        .reg_wdata(reg_wdata),
        .reg_wen(reg_wen),
        .reg_ren(reg_ren),
        .reg_rdata(reg_rdata),
        .reg_rvalid(reg_rvalid),
        .mac_start(mac_start),
        .mac_precision_mode(mac_precision_mode),
        .mac_done(mac_done),
        .mac_overflow(mac_overflow),
        .mac_count(mac_count),
        .dma_start(dma_start),
        .dma_src_addr(dma_src_addr),
        .dma_dst_addr(dma_dst_addr),
        .dma_length(dma_length),
        .dma_dir(dma_dir),
        .dma_done(dma_done),
        .dma_error(dma_error),
        .inference_done(inference_done),
        .inference_error(inference_error),
        .layer_index(layer_index),
        .inference_latency(inference_latency)
    );

    // Memory subsystem
    memory_subsystem u_memory (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tvalid(mac_to_mem_tvalid), // Results from MAC array
        .s_axis_tready(mac_to_mem_tready),
        .s_axis_tdata(mac_to_mem_tdata),
        .s_axis_tlast(mac_to_mem_tlast),
        .m_axis_tvalid(mem_to_mac_tvalid), // Data to MAC array
        .m_axis_tready(mem_to_mac_tready),
        .m_axis_tdata(mem_to_mac_tdata),
        .m_axis_tlast(),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .dma_start(dma_start),
        .dma_src_addr(dma_src_addr),
        .dma_dst_addr(dma_dst_addr),
        .dma_length(dma_length),
        .dma_dir(dma_dir),
        .dma_done(dma_done),
        .dma_error(dma_error)
    );

    // Internal AXI4-Stream connections
    logic mac_to_mem_tvalid;
    logic mac_to_mem_tready;
    logic [511:0] mac_to_mem_tdata;
    logic mac_to_mem_tlast;
    logic mem_to_mac_tvalid;
    logic mem_to_mac_tready;
    logic [511:0] mem_to_mac_tdata;

    // MAC array
    mac_array #(
        .N(MAC_N),
        .M(MAC_M),
        .MODE("INT8")
    ) u_mac (
        .clk(clk),
        .rst_n(rst_n),
        .start(mac_start),
        .done(mac_done),
        .precision_mode(mac_precision_mode),
        .s_axis_w_tvalid(mem_to_mac_tvalid), // Weights from memory
        .s_axis_w_tready(mem_to_mac_tready),
        .s_axis_w_tdata(mem_to_mac_tdata),
        .s_axis_a_tvalid(s_axis_tvalid), // Activations from external
        .s_axis_a_tready(),
        .s_axis_a_tdata(s_axis_tdata),
        .m_axis_r_tvalid(mac_to_mem_tvalid), // Results to memory
        .m_axis_r_tready(mac_to_mem_tready),
        .m_axis_r_tdata(mac_to_mem_tdata),
        .m_axis_r_tlast(mac_to_mem_tlast),
        .mac_count(mac_count),
        .overflow(mac_overflow)
    );

    // Interrupt generation
    assign interrupt = inference_done || inference_error;

    // PCIe interface (placeholder - would integrate with PCIe IP core)
    // In actual implementation, this would include clock domain crossing
    // and protocol conversion between PCIe and AXI4

endmodule
