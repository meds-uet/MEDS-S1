module control_register (
    input  logic        clk,
    input  logic        rst,

    input  logic        write_en,
    input  logic [31:0] write_data,

    output logic        enable,
    output logic        irq_en,
    output logic        cpol,
    output logic        cpha
);

    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin
            enable <= 1'b0;
            irq_en <= 1'b0;
            cpol   <= 1'b0;
            cpha   <= 1'b0;
        end

        else if (write_en) begin
            enable <= write_data[0];
            irq_en <= write_data[1];
            cpol   <= write_data[2];
            cpha   <= write_data[3];
        end

    end

endmodule