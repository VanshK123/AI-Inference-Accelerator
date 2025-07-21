`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

module testbench_top;
    logic clk = 0;
    logic rst = 1;
    always #5 clk = ~clk;

    initial begin
        #20 rst = 0;
    end

    top_level dut(
        .clk(clk), .rst(rst),
        .s_axi_awvalid(0), .s_axi_awready(), .s_axi_awaddr(0),
        .s_axi_wvalid(0), .s_axi_wdata(0), .s_axi_wready(),
        .s_axi_rdata(), .s_axi_rvalid(), .s_axi_rready(0),
        .s_axis_tvalid(0), .s_axis_tready(),
        .s_axis_tdata(0), .s_axis_tlast(0),
        .m_axis_tvalid(), .m_axis_tready(0), .m_axis_tdata(), .m_axis_tlast(),
        .pcie_clk(clk), .pcie_rst(rst), .pcie_tx(), .pcie_rx(0)
    );

    initial begin
        run_test();
    end
endmodule
