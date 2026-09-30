module sclk_generator (
    input  logic clk,
    input  logic rst,

    input  logic enable,
    input  logic tick,

    input  logic cpol,

    output logic sclk,
    output logic sck_rising,
    output logic sck_falling
);

    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin
            sclk        <= 1'b0;
            sck_rising  <= 1'b0;
            sck_falling <= 1'b0;
        end

        else begin

            // Edge indicators are pulses.
            sck_rising  <= 1'b0;
            sck_falling <= 1'b0;

            // -------------------------------------------------
            // SPI disabled
            // -------------------------------------------------

            if (!enable) begin
                sclk <= cpol;
            end

            // -------------------------------------------------
            // Generate SCLK edge
            // -------------------------------------------------

            else if (tick) begin

                if (sclk == 1'b0) begin
                    // 0 -> 1
                    sclk       <= 1'b1;
                    sck_rising <= 1'b1;
                end

                else begin
                    // 1 -> 0
                    sclk        <= 1'b0;
                    sck_falling  <= 1'b1;
                end

            end

        end

    end

endmodule

