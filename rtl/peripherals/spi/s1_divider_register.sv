module divider_register (
    input  logic        clk,
    input  logic        rst,

    input  logic        write_en,
    input  logic [31:0] write_data,

    output logic [15:0] divider
);

    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin
            divider <= 16'd100; //default 100
        end

        else if (write_en) begin
            divider <= write_data[15:0]; //capture lower 16 bits of 32 bits bus
        end

    end

endmodule