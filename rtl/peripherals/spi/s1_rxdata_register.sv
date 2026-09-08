module rxdata_register #(
    parameter WIDTH = 8
)(
    input  logic             clk,
    input  logic             rst,

    input  logic             capture_en,
    input  logic [WIDTH-1:0] rx_shift_data,

    output logic [WIDTH-1:0] rx_data
);

    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin
            rx_data <= '0;
        end

        else if (capture_en) begin
            rx_data <= rx_shift_data;
        end

    end

endmodule


