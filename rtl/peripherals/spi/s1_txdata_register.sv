module txdata_register #(
    parameter WIDTH = 8
)(
    input  logic             clk,
    input  logic             rst,

    input  logic             write_en,
    input  logic [WIDTH-1:0] write_data,

    output logic [WIDTH-1:0] tx_data
);

    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin
            tx_data <= '0;
        end

        else if (write_en) begin
            tx_data <= write_data;
        end

    end

endmodule

