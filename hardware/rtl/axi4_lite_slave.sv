// AXI4-Lite slave interface for control plane register access
module axi4_lite_slave #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    input  logic aclk,
    input  logic aresetn,
    // Write address channel
    input  logic [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic [2:0] s_axi_awprot,
    input  logic s_axi_awvalid,
    output logic s_axi_awready,
    // Write data channel
    input  logic [DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  logic s_axi_wvalid,
    output logic s_axi_wready,
    // Write response channel
    output logic [1:0] s_axi_bresp,
    output logic s_axi_bvalid,
    input  logic s_axi_bready,
    // Read address channel
    input  logic [ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic [2:0] s_axi_arprot,
    input  logic s_axi_arvalid,
    output logic s_axi_arready,
    // Read data channel
    output logic [DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0] s_axi_rresp,
    output logic s_axi_rvalid,
    input  logic s_axi_rready,
    // Register interface to control sequencer
    output logic [ADDR_WIDTH-1:0] reg_addr,
    output logic [DATA_WIDTH-1:0] reg_wdata,
    output logic reg_wen,
    output logic reg_ren,
    input  logic [DATA_WIDTH-1:0] reg_rdata,
    input  logic reg_rvalid
);

    enum logic [2:0] {
        IDLE,
        WRITE_ADDR,
        WRITE_DATA,
        WRITE_RESP,
        READ_ADDR,
        READ_DATA
    } state, next_state;

    logic [ADDR_WIDTH-1:0] awaddr_reg;
    logic [ADDR_WIDTH-1:0] araddr_reg;

    // State machine
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            state <= IDLE;
            awaddr_reg <= 0;
            araddr_reg <= 0;
        end else begin
            state <= next_state;
            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_reg <= s_axi_awaddr;
            end
            if (s_axi_arvalid && s_axi_arready) begin
                araddr_reg <= s_axi_araddr;
            end
        end
    end

    // Next state logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (s_axi_awvalid) begin
                    next_state = WRITE_ADDR;
                end else if (s_axi_arvalid) begin
                    next_state = READ_ADDR;
                end
            end
            WRITE_ADDR: begin
                if (s_axi_wvalid) begin
                    next_state = WRITE_DATA;
                end
            end
            WRITE_DATA: begin
                next_state = WRITE_RESP;
            end
            WRITE_RESP: begin
                if (s_axi_bready) begin
                    next_state = IDLE;
                end
            end
            READ_ADDR: begin
                next_state = READ_DATA;
            end
            READ_DATA: begin
                if (s_axi_rready) begin
                    next_state = IDLE;
                end
            end
        endcase
    end

    // Write address channel
    assign s_axi_awready = (state == IDLE || state == WRITE_ADDR) && s_axi_awvalid;

    // Write data channel
    assign s_axi_wready = (state == WRITE_ADDR || state == WRITE_DATA) && s_axi_wvalid;

    // Write response channel
    assign s_axi_bresp = 2'b00; // OKAY
    assign s_axi_bvalid = (state == WRITE_RESP);

    // Read address channel
    assign s_axi_arready = (state == IDLE || state == READ_ADDR) && s_axi_arvalid;

    // Read data channel
    assign s_axi_rdata = reg_rdata;
    assign s_axi_rresp = 2'b00; // OKAY
    assign s_axi_rvalid = (state == READ_DATA);

    // Register interface
    assign reg_addr = (state == WRITE_DATA || state == READ_DATA) ? 
                      ((state == WRITE_DATA) ? awaddr_reg : araddr_reg) : 0;
    assign reg_wdata = s_axi_wdata;
    assign reg_wen = (state == WRITE_DATA);
    assign reg_ren = (state == READ_ADDR);

endmodule

