module mac_assertions #(parameter N=4, M=4) (
    input logic clk,
    input logic rst,
    input logic in_valid,
    input logic out_valid
);

    property handshake;
        @(posedge clk) disable iff(rst)
        in_valid |-> ##1 out_valid;
    endproperty
    assert property(handshake);

    property no_overflow;
        @(posedge clk) disable iff(rst)
        $stable(out_valid);
    endproperty
    assert property(no_overflow);
endmodule
