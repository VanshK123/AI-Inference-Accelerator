// Parameterizable NxM systolic MAC array
module mac_array #(
    parameter int N = 4,
    parameter int M = 4,
    parameter string MODE = "INT8"   // INT8, INT16, FLOAT16
)(
    input  logic clk,
    input  logic rst,
    // handshake on input
    input  logic in_valid,
    output logic in_ready,
    input  logic [N*M*16-1:0] a, // flattened matrix A
    input  logic [N*M*16-1:0] b,
    // handshake on output
    output logic out_valid,
    input  logic out_ready,
    output logic [N*M*32-1:0] result
);

    localparam int DATA_W = (MODE == "FLOAT16") ? 16 : ((MODE == "INT16") ? 16 : 8);
    localparam int ACC_W  = DATA_W*2;

    typedef logic [DATA_W-1:0] data_t;
    typedef logic [ACC_W-1:0]  acc_t;

    data_t a_mat [N][M];
    data_t b_mat [N][M];
    acc_t  acc   [N][M];

    integer i,j;
    assign in_ready = out_ready; // simple flow control

    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid <= 0;
            for (i=0;i<N;i++)
                for (j=0;j<M;j++)
                    acc[i][j] <= 0;
        end else begin
            if (in_valid && in_ready) begin
                for (i=0;i<N;i++) begin
                    for (j=0;j<M;j++) begin
                        a_mat[i][j] <= a[(i*M+j)*16 +: 16];
                        b_mat[i][j] <= b[(i*M+j)*16 +: 16];
                        acc[i][j] <= a_mat[i][j] * b_mat[i][j];
                    end
                end
                out_valid <= 1;
            end else if (out_ready) begin
                out_valid <= 0;
            end
        end
    end

    // pack results
    generate
        genvar x,y;
        for (x=0; x<N; x++)
            for (y=0; y<M; y++)
                assign result[(x*M+y)*ACC_W +: ACC_W] = acc[x][y];
    endgenerate
endmodule
