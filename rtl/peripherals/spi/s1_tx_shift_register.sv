module tx_shift_register #(
    parameter WIDTH = 8
)(
    input  logic             clk,
    input  logic             rst,

    input  logic             load,
    input  logic             shift_en,

    input  logic [WIDTH-1:0] parallel_data,

    output logic             mosi,
    output logic [WIDTH-1:0] data
);

    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin
            data <= '0;
        end

        else if (load) begin
            data <= parallel_data;
        end

        else if (shift_en) begin
            data <= {data[WIDTH-2:0], 1'b0};
            //same logic as rxshift just we add a zero in place of the shifted bit
        end

    end

    assign mosi = data[WIDTH-1];

endmodule

