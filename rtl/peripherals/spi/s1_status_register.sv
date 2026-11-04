module status_register (
    input  logic        clk,
    input  logic        rst,

    input  logic        tx_full,
    input  logic        tx_empty,

    input  logic        rx_full,
    input  logic        rx_empty,

    input  logic        busy,
    input  logic        irq,

    output logic [31:0] status
);

    always_comb begin

        status = 32'd0;

        status[0] = tx_full;
        status[1] = tx_empty;

        status[2] = rx_full;
        status[3] = rx_empty;

        status[4] = busy;
        status[5] = irq;

    end

endmodule

