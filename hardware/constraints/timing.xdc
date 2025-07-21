# Primary 200 MHz reference clock
define_property PACKAGE_PIN <REF_CLK_PIN> [get_ports ref_clk]
create_clock -name ref_clk -period 5.000 [get_ports ref_clk]

# PCIe lane constraints
set_property IOSTANDARD LVDS [get_ports {PCIE_TX* PCIE_RX*}]
set_property DRIVE 8 [get_ports {PCIE_TX*}]
set_property SLEW FAST [get_ports {PCIE_TX* PCIE_RX*}]

# Voltage references per bank
set_property INTERNAL_VREF 0.75 [get_iobanks 128]
set_property INTERNAL_VREF 0.75 [get_iobanks 129]

# False paths between asynchronous clock domains
set_clock_groups -asynchronous -group [get_clocks ref_clk] -group [get_clocks pcie_clk]
