module rx_shift_register #(
    parameter WIDTH = 8
)(
    input  logic             clk,
    input  logic             rst,

    input  logic             shift_en,

    input  logic             miso,

    output logic [WIDTH-1:0] data
);

    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin
            data <= '0;
        end

        else if (shift_en) begin
            data <= {data[WIDTH-2:0], miso};
            //data[WIDTH-2:0] dels the last bit
            //miso adds one bit on the msb side which will move right
        end

    end

endmodule